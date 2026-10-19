import 'dart:convert';

import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';
import 'package:postgres/postgres.dart';

/// Valoraciones (inicial y final) del recorrido del paciente: coordinación
/// las abre con sus sesiones previstas por especialidad (de 1 a 20 en total),
/// las ajusta y las cierra con su resultado.
class ValoracionesCoordinacion {
  ValoracionesCoordinacion(this._db);

  final BaseDatos _db;

  static const _resultados = {
    'INICIAL': {'INGRESA_A_PROGRAMA', 'NO_REQUIERE'},
    'FINAL': {'ALTA', 'CONTINUA', 'DERIVADO'},
  };

  Future<void> _pacienteVisible(Session tx, Alcance a, String pacienteId) async {
    final r = await fila(tx, 'SELECT 1 FROM personas.pacientes pa WHERE pa.id = CAST(@id:text AS uuid) AND ${Alcance.paciente('pa')}',
        {...a.parametros, 'id': pacienteId});
    if (r == null) throw ErrorDatos(404, 'Ese estudiante no está en tu coordinación.');
  }

  /// Proceso de la coordinación (por su estudiante) o error 404.
  Future<Map<String, dynamic>> _proceso(Session tx, Alcance a, String id) async {
    final r = await fila(tx, '''
      SELECT pv.id::text, pv.tipo, pv.estado, pv.paciente_id::text FROM agenda.procesos_valoracion pv
      JOIN personas.pacientes pa ON pa.id = pv.paciente_id
      WHERE pv.id = CAST(@id:text AS uuid) AND ${Alcance.paciente('pa')}''', {...a.parametros, 'id': id});
    if (r == null) throw ErrorDatos(404, 'Esa valoración no existe o no es de tu coordinación.');
    return r;
  }

  /// [{sub_area_id, sesiones}] validado: al menos una especialidad, sesiones de 1 en adelante.
  static List<Map<String, Object?>> _plan(Object? valor) {
    final plan = [for (final x in (valor as List?) ?? const []) (x as Map).cast<String, dynamic>()];
    if (plan.isEmpty) throw ErrorDatos(422, 'Elige al menos una especialidad para la valoración.');
    for (final x in plan) {
      if ('${x['sub_area_id'] ?? ''}'.isEmpty) throw ErrorDatos(422, 'Falta la especialidad.');
      final n = x['sesiones'];
      if (n is! int || n < 1) throw ErrorDatos(422, 'Cada especialidad lleva al menos una sesión.');
    }
    return [for (final x in plan) {'sub_area_id': x['sub_area_id'], 'sesiones': x['sesiones']}];
  }

  /// Las especialidades deben poder hacer valoraciones de ese tipo.
  Future<void> _validarEspecialidades(Session tx, String tipo, List<Map<String, Object?>> plan) async {
    final validas = await fila(tx, '''
      SELECT count(*)::int AS n FROM jsonb_to_recordset(CAST(@plan:text AS jsonb)) p(sub_area_id uuid, sesiones int)
      WHERE EXISTS (SELECT 1 FROM catalogo.programas pg
                    WHERE pg.activo AND pg.valoracion = @tipo:text
                      AND (pg.sub_area_requerida_id = p.sub_area_id
                           OR EXISTS (SELECT 1 FROM catalogo.programa_especialidades pe
                                      WHERE pe.programa_id = pg.id AND pe.sub_area_id = p.sub_area_id)))''',
        {'plan': jsonEncode(plan), 'tipo': tipo});
    if (validas!['n'] != plan.length) {
      throw ErrorDatos(422, 'Alguna especialidad elegida no hace valoraciones ${tipo == 'INICIAL' ? 'iniciales' : 'finales'}.');
    }
  }

  /// Abre la valoración inicial o final de un estudiante.
  Future<Map<String, Object?>> abrir(Sesion s, Map<String, dynamic> d) {
    final a = Alcance.de(s);
    final tipo = d['tipo'] as String? ?? 'INICIAL';
    if (!_resultados.containsKey(tipo)) throw ErrorDatos(422, 'La valoración es INICIAL o FINAL.');
    final pacienteId = '${d['paciente_id'] ?? ''}';
    if (pacienteId.isEmpty) throw ErrorDatos(422, 'Falta el estudiante.');
    final plan = _plan(d['especialidades']);
    return _db.conSesion(s, (tx) async {
      await _pacienteVisible(tx, a, pacienteId);
      await _validarEspecialidades(tx, tipo, plan);
      final abierta = await fila(tx, '''
        SELECT 1 FROM agenda.procesos_valoracion
        WHERE paciente_id = CAST(@p:text AS uuid) AND tipo = @t:text AND estado = 'EN_CURSO' ''', {'p': pacienteId, 't': tipo});
      if (abierta != null) {
        throw ErrorDatos(409, 'Ya tiene una valoración ${tipo == 'INICIAL' ? 'inicial' : 'final'} en curso: ajústala en vez de abrir otra.');
      }
      String? matricula;
      if (tipo == 'FINAL') {
        final m = await fila(tx, '''
          SELECT id::text FROM matriculas.matriculas
          WHERE paciente_id = CAST(@p:text AS uuid) AND estado <> 'CANCELADA'
            AND (@m:text = '' OR id = CAST(nullif(@m:text, '') AS uuid))
          ORDER BY fecha_inicio DESC LIMIT 1''', {'p': pacienteId, 'm': d['matricula_id'] ?? ''});
        if (m == null) throw ErrorDatos(422, 'La valoración final es al terminar un programa, y este estudiante no tiene ninguno.');
        matricula = m['id'] as String;
      }
      final nuevo = await fila(tx, '''
        INSERT INTO agenda.procesos_valoracion (paciente_id, tipo, matricula_id, abierto_por)
        VALUES (CAST(@p:text AS uuid), @t:text, CAST(@m:text AS uuid), CAST(@u:text AS uuid))
        RETURNING id::text''', {'p': pacienteId, 't': tipo, 'm': matricula, 'u': s.usuarioId});
      await _guardarPlan(tx, nuevo!['id'] as String, plan);
      return nuevo;
    });
  }

  Future<void> _guardarPlan(Session tx, String procesoId, List<Map<String, Object?>> plan) async {
    // Lo que sale del plan se borra (si no tiene sesiones; si las tiene, la base lo impide).
    await consultar(tx, '''
      DELETE FROM agenda.proceso_especialidades pe
      WHERE pe.proceso_id = CAST(@id:text AS uuid)
        AND pe.sub_area_id NOT IN (SELECT (e ->> 'sub_area_id')::uuid FROM jsonb_array_elements(CAST(@plan:text AS jsonb)) e)''',
        {'id': procesoId, 'plan': jsonEncode(plan)});
    final quitadas = await fila(tx, '''
      SELECT count(*)::int AS n FROM agenda.participantes x
      WHERE x.proceso_valoracion_id = CAST(@id:text AS uuid)
        AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA')
        AND x.valoracion_especialidad_id NOT IN (SELECT (e ->> 'sub_area_id')::uuid FROM jsonb_array_elements(CAST(@plan:text AS jsonb)) e)''',
        {'id': procesoId, 'plan': jsonEncode(plan)});
    if (quitadas!['n'] != 0) throw ErrorDatos(422, 'No se puede quitar una especialidad que ya tiene sesiones agendadas o realizadas.');
    // Primero se bajan las que se reducen, para que el total no supere el máximo a mitad de camino.
    for (final x in [...plan]..sort((p, q) => (p['sesiones']! as int).compareTo(q['sesiones']! as int))) {
      await consultar(tx, '''
        INSERT INTO agenda.proceso_especialidades (proceso_id, sub_area_id, sesiones)
        VALUES (CAST(@id:text AS uuid), CAST(@sa:text AS uuid), @n:int4)
        ON CONFLICT (proceso_id, sub_area_id) DO UPDATE SET sesiones = EXCLUDED.sesiones''',
          {'id': procesoId, 'sa': x['sub_area_id'], 'n': x['sesiones']});
    }
  }

  /// Cambia las sesiones previstas por especialidad de una valoración en curso.
  Future<void> ajustar(Sesion s, String id, Map<String, dynamic> d) {
    final a = Alcance.de(s);
    final plan = _plan(d['especialidades']);
    return _db.conSesion(s, (tx) async {
      final p = await _proceso(tx, a, id);
      if (p['estado'] != 'EN_CURSO') throw ErrorDatos(422, 'Esa valoración ya está cerrada.');
      await _validarEspecialidades(tx, p['tipo'] as String, plan);
      await _guardarPlan(tx, id, plan);
    });
  }

  /// Cierra la valoración con su resultado. Necesita al menos una sesión
  /// realizada y ninguna pendiente. El alta de la valoración final gradúa al estudiante.
  Future<void> cerrar(Sesion s, String id, Map<String, dynamic> d) {
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async {
      final p = await _proceso(tx, a, id);
      if (p['estado'] != 'EN_CURSO') throw ErrorDatos(422, 'Esa valoración ya está cerrada.');
      final tipo = p['tipo'] as String;
      final resultado = d['resultado'] as String?;
      if (!_resultados[tipo]!.contains(resultado)) {
        throw ErrorDatos(422, 'Resultado no válido para una valoración ${tipo.toLowerCase()}: ${_resultados[tipo]!.join(', ')}.');
      }
      final sesiones = await fila(tx, '''
        SELECT count(*) FILTER (WHERE asistencia = 'ASISTIO')::int AS realizadas,
               count(*) FILTER (WHERE asistencia = 'PENDIENTE')::int AS pendientes
        FROM agenda.participantes WHERE proceso_valoracion_id = CAST(@id:text AS uuid)''', {'id': id});
      if (sesiones!['realizadas'] == 0) throw ErrorDatos(422, 'Para cerrar la valoración debe haber al menos una sesión realizada.');
      if (sesiones['pendientes'] != 0) {
        throw ErrorDatos(422, 'Quedan ${sesiones['pendientes']} sesiones agendadas: espera a que se realicen o cancélalas.');
      }
      await consultar(tx, '''
        UPDATE agenda.procesos_valoracion
           SET estado = 'COMPLETADA', resultado = @r:text, conclusion = nullif(trim(@c:text), ''),
               programa_recomendado_id = CAST(nullif(@pr:text, '') AS uuid), cerrado_en = now(), cerrado_por = CAST(@u:text AS uuid)
         WHERE id = CAST(@id:text AS uuid)''',
          {'r': resultado, 'c': d['conclusion'] ?? '', 'pr': d['programa_recomendado_id'] ?? '', 'u': s.usuarioId, 'id': id});
      if (resultado == 'ALTA') {
        await consultar(tx, "UPDATE personas.pacientes SET estado = 'GRADUADO', actualizado_por = CAST(@u:text AS uuid) WHERE id = CAST(@p:text AS uuid)",
            {'u': s.usuarioId, 'p': p['paciente_id']});
      }
    });
  }

  /// Anula una valoración abierta por error (sin sesiones realizadas).
  Future<void> cancelar(Sesion s, String id) {
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async {
      final p = await _proceso(tx, a, id);
      if (p['estado'] != 'EN_CURSO') throw ErrorDatos(422, 'Esa valoración ya está cerrada.');
      final usadas = await fila(tx, '''
        SELECT count(*)::int AS n FROM agenda.participantes
        WHERE proceso_valoracion_id = CAST(@id:text AS uuid) AND asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')''', {'id': id});
      if (usadas!['n'] != 0) throw ErrorDatos(422, 'La valoración ya tiene sesiones: cancélalas primero o ciérrala con su resultado.');
      await consultar(tx, '''
        UPDATE agenda.procesos_valoracion SET estado = 'CANCELADA', cerrado_en = now(), cerrado_por = CAST(@u:text AS uuid)
        WHERE id = CAST(@id:text AS uuid)''', {'u': s.usuarioId, 'id': id});
    });
  }
}
