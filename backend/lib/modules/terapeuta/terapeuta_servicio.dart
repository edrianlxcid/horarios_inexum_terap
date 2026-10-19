import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';
import 'package:backend/modules/recorrido/recorrido.dart';
import 'package:postgres/postgres.dart';

/// Portal del terapeuta: solo ve sus sesiones y a sus pacientes.
class TerapeutaServicio {
  TerapeutaServicio(this._db, this._llave);

  final BaseDatos _db;
  final String _llave;

  static const _asistenciasPermitidas = {'PENDIENTE', 'ASISTIO', 'FALTA', 'FALTA_JUSTIFICADA'};

  Future<String> _profesional(Session tx, Sesion s) async {
    final r = await fila(tx, 'SELECT id::text FROM personas.profesionales WHERE usuario_id = CAST(@u:text AS uuid)',
        {'u': s.usuarioId});
    if (r == null) throw ErrorAcceso(403, 'Tu usuario no está registrado como terapeuta en esta empresa.');
    return r['id'] as String;
  }

  /// Sesiones del terapeuta entre dos fechas, con sus participantes.
  Future<Map<String, Object?>> agenda(Sesion s, String desde, String hasta) => _db.conSesion(s, (tx) async {
        final prof = await _profesional(tx, s);
        final datos = await fila(tx, '''
          SELECT id::text, nombres || ' ' || apellidos AS nombre, profesion
          FROM personas.profesionales WHERE id = CAST(@p:text AS uuid)''', {'p': prof});
        final sesiones = await filas(tx, '''
          SELECT s.id::text AS id,
                 to_char(s.inicio AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS inicio,
                 to_char(s.fin AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS fin,
                 s.tipo, s.estado, s.cupo_maximo, se.nombre AS sede, sa.nombre AS sala,
                 pg.nombre AS programa, g.codigo AS grupo,
                 coalesce((
                   SELECT json_agg(json_build_object(
                            'participante_id', p.id, 'paciente_id', pa.id,
                            'paciente', pa.nombres || ' ' || pa.apellidos,
                            'edad_meses', (extract(year FROM age(pa.fecha_nacimiento)) * 12
                                          + extract(month FROM age(pa.fecha_nacimiento)))::int,
                            'numero_sesion', p.numero_sesion,
                            'total_sesiones', coalesce(m.sesiones_contratadas,
                                (SELECT sum(pe.sesiones) FROM agenda.proceso_especialidades pe
                                 WHERE pe.proceso_id = p.proceso_valoracion_id))::int,
                            'valoracion', pv.tipo, 'especialidad', esp.nombre,
                            'fase', f.nombre, 'asistencia', p.asistencia, 'demanda', nd.nombre,
                            'trabajado', n.resumen_familia,
                            'nota', CASE WHEN n.id IS NULL THEN 'SIN_NOTA'
                                         WHEN n.firmada_en IS NULL THEN 'BORRADOR' ELSE 'FIRMADA' END)
                          ORDER BY pa.nombres)
                   FROM agenda.participantes p
                   JOIN personas.pacientes pa ON pa.id = p.paciente_id
                   LEFT JOIN matriculas.matriculas m ON m.id = p.matricula_id
                   LEFT JOIN agenda.procesos_valoracion pv ON pv.id = p.proceso_valoracion_id
                   LEFT JOIN catalogo.sub_areas esp ON esp.id = p.valoracion_especialidad_id
                   LEFT JOIN catalogo.programa_fases f ON f.id = p.fase_id
                   LEFT JOIN personas.clasificaciones_demanda cd ON cd.paciente_id = pa.id AND cd.vigente
                   LEFT JOIN personas.niveles_demanda nd ON nd.id = cd.nivel_id
                   LEFT JOIN clinico.notas_sesion n ON n.participante_id = p.id
                   WHERE p.sesion_id = s.id AND p.asistencia <> 'REPROGRAMADA'), '[]'::json) AS participantes
          FROM agenda.sesiones s
          JOIN organizacion.sedes se ON se.id = s.sede_id
          LEFT JOIN organizacion.salas sa ON sa.id = s.sala_id
          LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
          LEFT JOIN agenda.grupos g ON g.id = s.grupo_id
          WHERE s.profesional_id = CAST(@p:text AS uuid)
            AND (s.inicio AT TIME ZONE se.zona_horaria)::date BETWEEN CAST(@d:text AS date) AND CAST(@h:text AS date)
          ORDER BY s.inicio''', {'p': prof, 'd': desde, 'h': hasta});
        return {'terapeuta': datos, 'desde': desde, 'hasta': hasta, 'sesiones': sesiones};
      });

  /// Marca la asistencia de un participante de una sesión propia (de hoy o pasada).
  Future<void> marcarAsistencia(Sesion s, String participanteId, String asistencia) {
    if (!_asistenciasPermitidas.contains(asistencia)) {
      throw ErrorDatos(422, 'Asistencia no válida. Usa: ${_asistenciasPermitidas.join(', ')}.');
    }
    return _db.conSesion(s, (tx) async {
      final prof = await _profesional(tx, s);
      final sesion = await fila(tx, '''
        SELECT s.id::text, (s.inicio AT TIME ZONE se.zona_horaria)::date > (now() AT TIME ZONE se.zona_horaria)::date AS futura
        FROM agenda.participantes p
        JOIN agenda.sesiones s ON s.id = p.sesion_id
        JOIN organizacion.sedes se ON se.id = s.sede_id
        WHERE p.id = CAST(@id:text AS uuid) AND s.profesional_id = CAST(@p:text AS uuid)''', {'id': participanteId, 'p': prof});
      if (sesion == null) throw ErrorDatos(404, 'No encontramos ese paciente en tus sesiones.');
      if (sesion['futura'] == true) throw ErrorDatos(422, 'No puedes marcar asistencia de una sesión futura.');
      await consultar(tx, '''
        UPDATE agenda.participantes
           SET asistencia = @a:text,
               marcado_por = CASE WHEN @a:text = 'PENDIENTE' THEN NULL ELSE CAST(@u:text AS uuid) END,
               marcado_en = CASE WHEN @a:text = 'PENDIENTE' THEN NULL ELSE now() END
         WHERE id = CAST(@id:text AS uuid)''', {'a': asistencia, 'u': s.usuarioId, 'id': participanteId});
      await consultar(tx, '''
        UPDATE agenda.sesiones SET estado = 'REALIZADA'
        WHERE id = CAST(@s:text AS uuid) AND estado = 'PROGRAMADA' AND @a:text <> 'PENDIENTE' ''',
          {'s': sesion['id'], 'a': asistencia});
    });
  }

  /// Nota de una sesión (descifrada) y los objetivos de la matrícula.
  Future<Map<String, Object?>> nota(Sesion s, String participanteId) => _db.conSesion(s, (tx) async {
        final prof = await _profesional(tx, s);
        final datos = await fila(tx, '''
          SELECT p.id::text AS participante_id, pa.id::text AS paciente_id, pa.nombres || ' ' || pa.apellidos AS paciente,
                 to_char(s.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD HH24:MI') AS inicio,
                 pg.nombre AS programa, p.numero_sesion, p.asistencia, p.matricula_id::text AS matricula_id,
                 n.id::text AS nota_id, comun.descifrar(n.contenido, @llave:text) AS contenido, n.resumen_familia,
                 to_char(n.firmada_en AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD HH24:MI') AS firmada_en
          FROM agenda.participantes p
          JOIN agenda.sesiones s ON s.id = p.sesion_id
          JOIN personas.pacientes pa ON pa.id = p.paciente_id
          LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
          LEFT JOIN clinico.notas_sesion n ON n.participante_id = p.id
          WHERE p.id = CAST(@id:text AS uuid) AND s.profesional_id = CAST(@p:text AS uuid)''',
            {'id': participanteId, 'p': prof, 'llave': _llave});
        if (datos == null) throw ErrorDatos(404, 'No encontramos ese paciente en tus sesiones.');
        if (datos['nota_id'] != null) {
          await consultar(tx, "SELECT seguridad.registrar_lectura('clinico.notas_sesion', @n:text)", {'n': datos['nota_id']});
        }
        final objetivos = datos['matricula_id'] == null
            ? <Map<String, dynamic>>[]
            : await filas(tx, '''
                SELECT o.id::text, o.descripcion, o.estado,
                       (SELECT a.nivel FROM clinico.avances_objetivo a WHERE a.objetivo_id = o.id
                        ORDER BY a.registrado_en DESC LIMIT 1) AS ultimo_nivel
                FROM clinico.objetivos o WHERE o.matricula_id = CAST(@m:text AS uuid) ORDER BY o.fecha_inicio''',
                {'m': datos['matricula_id']});
        return {...datos, 'objetivos': objetivos};
      });

  /// Crea o actualiza la nota. Firmada, ya no se puede cambiar (lo impide la base).
  Future<void> guardarNota(
    Sesion s,
    String participanteId, {
    required String contenido,
    String? resumenFamilia,
    bool firmar = false,
    List<Map<String, dynamic>> avances = const [],
  }) =>
      _db.conSesion(s, (tx) async {
        final prof = await _profesional(tx, s);
        final p = await fila(tx, '''
          SELECT p.asistencia, p.matricula_id::text AS matricula_id
          FROM agenda.participantes p JOIN agenda.sesiones s ON s.id = p.sesion_id
          WHERE p.id = CAST(@id:text AS uuid) AND s.profesional_id = CAST(@p:text AS uuid)''', {'id': participanteId, 'p': prof});
        if (p == null) throw ErrorDatos(404, 'No encontramos ese paciente en tus sesiones.');
        if (p['asistencia'] != 'ASISTIO') throw ErrorDatos(422, 'Solo se registra nota de pacientes que asistieron.');
        final nota = await fila(tx, '''
          INSERT INTO clinico.notas_sesion (participante_id, profesional_id, contenido, resumen_familia, firmada_en)
          VALUES (CAST(@id:text AS uuid), CAST(@p:text AS uuid), comun.cifrar(@c:text, @llave:text), @r:text,
                  CASE WHEN @f:boolean THEN now() END)
          ON CONFLICT (participante_id) DO UPDATE
            SET contenido = EXCLUDED.contenido, resumen_familia = EXCLUDED.resumen_familia,
                firmada_en = EXCLUDED.firmada_en
          RETURNING id::text''', {'id': participanteId, 'p': prof, 'c': contenido, 'llave': _llave, 'r': resumenFamilia, 'f': firmar});
        for (final a in avances) {
          final nivel = a['nivel'];
          if (nivel is! int || nivel < 1 || nivel > 5) throw ErrorDatos(422, 'El nivel de avance va de 1 a 5.');
          await consultar(tx, '''
            INSERT INTO clinico.avances_objetivo (objetivo_id, nota_id, nivel, comentario)
            SELECT o.id, CAST(@n:text AS uuid), @nivel:int4, @c:text FROM clinico.objetivos o
            WHERE o.id = CAST(@o:text AS uuid) AND o.matricula_id = CAST(@m:text AS uuid)''',
              {'n': nota!['id'], 'nivel': nivel, 'c': a['comentario'], 'o': a['objetivo_id'], 'm': p['matricula_id']});
        }
      });

  /// Ficha resumida de un paciente que el terapeuta atiende.
  Future<Map<String, Object?>> paciente(Sesion s, String pacienteId) => _db.conSesion(s, (tx) async {
        final prof = await _profesional(tx, s);
        final datos = await fila(tx, '''
          SELECT pa.id::text, pa.codigo_historia, pa.nombres, pa.apellidos, to_char(pa.fecha_nacimiento, 'YYYY-MM-DD') AS fecha_nacimiento,
                 (extract(year FROM age(pa.fecha_nacimiento)) * 12 + extract(month FROM age(pa.fecha_nacimiento)))::int AS edad_meses,
                 pa.estado, se.nombre AS sede, nd.nombre AS demanda, cd.motivo AS motivo_demanda
          FROM personas.pacientes pa
          JOIN organizacion.sedes se ON se.id = pa.sede_principal_id
          LEFT JOIN personas.clasificaciones_demanda cd ON cd.paciente_id = pa.id AND cd.vigente
          LEFT JOIN personas.niveles_demanda nd ON nd.id = cd.nivel_id
          WHERE pa.id = CAST(@id:text AS uuid)
            AND EXISTS (SELECT 1 FROM agenda.participantes p JOIN agenda.sesiones s ON s.id = p.sesion_id
                        WHERE p.paciente_id = pa.id AND s.profesional_id = CAST(@p:text AS uuid))''', {'id': pacienteId, 'p': prof});
        if (datos == null) throw ErrorDatos(404, 'Ese paciente no está en tus sesiones.');
        await consultar(tx, "SELECT seguridad.registrar_lectura('personas.pacientes', @id:text)", {'id': pacienteId});
        final id = {'id': pacienteId, 'llave': _llave};
        return {
          ...datos,
          'representantes': await filas(tx, '''
            SELECT r.nombres || ' ' || r.apellidos AS nombre, pr.parentesco, r.telefono, pr.es_principal
            FROM personas.paciente_representantes pr JOIN personas.representantes r ON r.id = pr.representante_id
            WHERE pr.paciente_id = CAST(@id:text AS uuid) ORDER BY pr.es_principal DESC''', id),
          'matriculas': await filas(tx, '''
            SELECT v.matricula_id::text AS id, pg.nombre AS programa, v.estado, v.sesiones_contratadas::int,
                   v.sesiones_consumidas::int, f.nombre AS fase
            FROM matriculas.v_saldo_sesiones v
            JOIN matriculas.matriculas m ON m.id = v.matricula_id
            JOIN catalogo.programas pg ON pg.id = v.programa_id
            LEFT JOIN catalogo.programa_fases f ON f.id = m.fase_actual_id
            WHERE v.paciente_id = CAST(@id:text AS uuid) ORDER BY m.fecha_inicio DESC''', id),
          'objetivos': await filas(tx, '''
            SELECT o.id::text, o.descripcion, o.estado, pg.nombre AS programa,
                   (SELECT a.nivel FROM clinico.avances_objetivo a WHERE a.objetivo_id = o.id
                    ORDER BY a.registrado_en DESC LIMIT 1) AS ultimo_nivel
            FROM clinico.objetivos o JOIN matriculas.matriculas m ON m.id = o.matricula_id
            JOIN catalogo.programas pg ON pg.id = m.programa_id
            WHERE m.paciente_id = CAST(@id:text AS uuid) ORDER BY o.estado, o.fecha_inicio''', id),
          // Recorrido: etapa y todas sus sesiones (con quién, si asistió y qué se
          // trabajó). Las propias se pueden abrir para ver o escribir la nota.
          'etapa': await Recorrido.etapa(tx, pacienteId),
          'profesional_id': prof,
          'linea_tiempo': await Recorrido.lineaDeTiempo(tx, pacienteId),
          'tareas': await filas(tx, '''
            SELECT t.id::text, t.titulo, t.descripcion, to_char(t.fecha_limite, 'YYYY-MM-DD') AS fecha_limite,
                   t.completada_en IS NOT NULL AS completada, t.comentario_familia
            FROM clinico.tareas_casa t WHERE t.paciente_id = CAST(@id:text AS uuid)
            ORDER BY t.fecha_asignada DESC LIMIT 10''', id),
        };
      });

  Future<void> asignarTarea(Sesion s, String pacienteId, {required String titulo, String? descripcion, String? fechaLimite}) =>
      _db.conSesion(s, (tx) async {
        final prof = await _profesional(tx, s);
        final r = await consultar(tx, '''
          INSERT INTO clinico.tareas_casa (paciente_id, profesional_id, titulo, descripcion, fecha_limite)
          SELECT pa.id, CAST(@p:text AS uuid), @t:text, @d:text, CAST(@f:text AS date)
          FROM personas.pacientes pa
          WHERE pa.id = CAST(@id:text AS uuid)
            AND EXISTS (SELECT 1 FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
                        WHERE x.paciente_id = pa.id AND s.profesional_id = CAST(@p:text AS uuid))''',
            {'p': prof, 't': titulo, 'd': descripcion, 'f': fechaLimite, 'id': pacienteId});
        if (r.affectedRows == 0) throw ErrorDatos(404, 'Ese paciente no está en tus sesiones.');
      });
}
