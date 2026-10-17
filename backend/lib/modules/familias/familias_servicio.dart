import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';
import 'package:postgres/postgres.dart';

/// Portal de familias: el representante solo ve a sus hijos.
/// No muestra pagos ni notas clínicas completas: solo el resumen para la familia.
class FamiliasServicio {
  FamiliasServicio(this._db);

  final BaseDatos _db;

  Future<String> _representante(Session tx, Sesion s) async {
    final r = await fila(tx, 'SELECT id::text FROM personas.representantes WHERE usuario_id = CAST(@u:text AS uuid)',
        {'u': s.usuarioId});
    if (r == null) throw ErrorAcceso(403, 'Tu usuario no está registrado como representante en esta empresa.');
    return r['id'] as String;
  }

  Future<void> _esHijo(Session tx, String representanteId, String pacienteId) async {
    final r = await fila(tx, '''
      SELECT 1 FROM personas.paciente_representantes
      WHERE representante_id = CAST(@r:text AS uuid) AND paciente_id = CAST(@p:text AS uuid)''',
        {'r': representanteId, 'p': pacienteId});
    if (r == null) throw ErrorDatos(404, 'No encontramos a ese paciente entre tus representados.');
  }

  Future<List<Map<String, dynamic>>> hijos(Sesion s) => _db.conSesion(s, (tx) async {
        final rep = await _representante(tx, s);
        return filas(tx, '''
          SELECT pa.id::text, pa.nombres, pa.apellidos, pa.estado, se.nombre AS sede, pr.parentesco,
                 (extract(year FROM age(pa.fecha_nacimiento)) * 12 + extract(month FROM age(pa.fecha_nacimiento)))::int AS edad_meses
          FROM personas.paciente_representantes pr
          JOIN personas.pacientes pa ON pa.id = pr.paciente_id
          JOIN organizacion.sedes se ON se.id = pa.sede_principal_id
          WHERE pr.representante_id = CAST(@r:text AS uuid) AND pa.archivado_en IS NULL
          ORDER BY pa.nombres''', {'r': rep});
      });

  /// Todo lo que la familia ve de un hijo en una sola respuesta.
  Future<Map<String, Object?>> resumen(Sesion s, String pacienteId) => _db.conSesion(s, (tx) async {
        final rep = await _representante(tx, s);
        await _esHijo(tx, rep, pacienteId);
        final p = {'p': pacienteId};
        return {
          'proximas_sesiones': await filas(tx, '''
            SELECT x.id::text AS participante_id,
                   to_char(s.inicio AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS inicio,
                   s.tipo, pg.nombre AS programa, pr.nombres || ' ' || pr.apellidos AS terapeuta, se.nombre AS sede,
                   x.numero_sesion,
                   EXISTS (SELECT 1 FROM agenda.solicitudes_cambio sc
                           WHERE sc.participante_id = x.id AND sc.estado = 'PENDIENTE') AS solicitud_pendiente
            FROM agenda.participantes x
            JOIN agenda.sesiones s ON s.id = x.sesion_id
            JOIN organizacion.sedes se ON se.id = s.sede_id
            JOIN personas.profesionales pr ON pr.id = s.profesional_id
            LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
            WHERE x.paciente_id = CAST(@p:text AS uuid) AND s.inicio >= now()
              AND s.estado <> 'CANCELADA' AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')
            ORDER BY s.inicio LIMIT 8''', p),
          'programas': await filas(tx, '''
            SELECT v.matricula_id::text AS matricula_id, pg.nombre AS programa, v.estado,
                   v.sesiones_contratadas::int AS contratadas, v.sesiones_consumidas::int AS realizadas,
                   f.nombre AS fase, to_char(m.fecha_fin_estimada, 'YYYY-MM-DD') AS fin_estimado
            FROM matriculas.v_saldo_sesiones v
            JOIN matriculas.matriculas m ON m.id = v.matricula_id
            JOIN catalogo.programas pg ON pg.id = v.programa_id
            LEFT JOIN catalogo.programa_fases f ON f.id = m.fase_actual_id
            WHERE v.paciente_id = CAST(@p:text AS uuid) ORDER BY m.fecha_inicio DESC''', p),
          'objetivos': await filas(tx, '''
            SELECT o.descripcion, o.estado, pg.nombre AS programa,
                   (SELECT a.nivel FROM clinico.avances_objetivo a WHERE a.objetivo_id = o.id
                    ORDER BY a.registrado_en DESC LIMIT 1) AS ultimo_nivel
            FROM clinico.objetivos o
            JOIN matriculas.matriculas m ON m.id = o.matricula_id
            JOIN catalogo.programas pg ON pg.id = m.programa_id
            WHERE m.paciente_id = CAST(@p:text AS uuid) AND m.estado IN ('EN_CURSO', 'CONGELADA', 'COMPLETADA')
            ORDER BY o.estado, o.fecha_inicio''', p),
          'tareas': await filas(tx, '''
            SELECT t.id::text, t.titulo, t.descripcion, to_char(t.fecha_limite, 'YYYY-MM-DD') AS fecha_limite,
                   t.completada_en IS NOT NULL AS completada, t.comentario_familia,
                   pr.nombres || ' ' || pr.apellidos AS terapeuta
            FROM clinico.tareas_casa t JOIN personas.profesionales pr ON pr.id = t.profesional_id
            WHERE t.paciente_id = CAST(@p:text AS uuid)
            ORDER BY t.completada_en IS NOT NULL, t.fecha_asignada DESC LIMIT 12''', p),
          'historial': await filas(tx, '''
            SELECT to_char(s.inicio AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD') AS fecha, pg.nombre AS programa,
                   pr.nombres || ' ' || pr.apellidos AS terapeuta, x.asistencia, x.numero_sesion,
                   CASE WHEN n.firmada_en IS NOT NULL THEN n.resumen_familia END AS resumen
            FROM agenda.participantes x
            JOIN agenda.sesiones s ON s.id = x.sesion_id
            JOIN organizacion.sedes se ON se.id = s.sede_id
            JOIN personas.profesionales pr ON pr.id = s.profesional_id
            LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
            LEFT JOIN clinico.notas_sesion n ON n.participante_id = x.id
            WHERE x.paciente_id = CAST(@p:text AS uuid) AND s.inicio < now()
            ORDER BY s.inicio DESC LIMIT 10''', p),
          'contratos_vigentes': await filas(tx, '''
            SELECT DISTINCT c.codigo, c.estado, to_char(c.vigente_desde, 'YYYY-MM-DD') AS vigente_desde,
                   to_char(c.vigente_hasta, 'YYYY-MM-DD') AS vigente_hasta
            FROM matriculas.contratos c JOIN matriculas.matriculas m ON m.contrato_id = c.id
            WHERE m.paciente_id = CAST(@p:text AS uuid) AND c.estado IN ('VIGENTE', 'CONGELADO')''', p),
          'evaluaciones_pendientes': await filas(tx, '''
            SELECT e.matricula_id::text, e.profesional_id::text, pr.nombres || ' ' || pr.apellidos AS terapeuta,
                   pg.nombre AS programa
            FROM desempeno.v_evaluaciones_pendientes e
            JOIN personas.profesionales pr ON pr.id = e.profesional_id
            JOIN matriculas.matriculas m ON m.id = e.matricula_id
            JOIN catalogo.programas pg ON pg.id = m.programa_id
            WHERE e.paciente_id = CAST(@p:text AS uuid)''', p),
        };
      });

  Future<List<Map<String, dynamic>>> escala() => _db.sinEmpresa(
        (tx) => filas(tx, 'SELECT valor, etiqueta FROM desempeno.escala_evaluacion ORDER BY valor'),
      );

  Future<void> completarTarea(Sesion s, String tareaId, String? comentario) => _db.conSesion(s, (tx) async {
        final rep = await _representante(tx, s);
        final r = await consultar(tx, '''
          UPDATE clinico.tareas_casa t SET completada_en = now(), comentario_familia = @c:text
          WHERE t.id = CAST(@t:text AS uuid) AND t.completada_en IS NULL
            AND EXISTS (SELECT 1 FROM personas.paciente_representantes pr
                        WHERE pr.paciente_id = t.paciente_id AND pr.representante_id = CAST(@r:text AS uuid))''',
            {'c': comentario, 't': tareaId, 'r': rep});
        if (r.affectedRows == 0) throw ErrorDatos(404, 'La tarea no existe o ya estaba completada.');
      });

  /// Evaluación obligatoria del terapeuta. La base valida que corresponda.
  Future<void> evaluar(Sesion s, {required String matriculaId, required String profesionalId, required int puntaje, String? comentario}) =>
      _db.conSesion(s, (tx) async {
        final rep = await _representante(tx, s);
        await consultar(tx, '''
          INSERT INTO desempeno.evaluaciones_terapeuta (matricula_id, profesional_id, representante_id, puntaje, comentario)
          VALUES (CAST(@m:text AS uuid), CAST(@p:text AS uuid), CAST(@r:text AS uuid), @n:int4, @c:text)''',
            {'m': matriculaId, 'p': profesionalId, 'r': rep, 'n': puntaje, 'c': comentario});
      });

  /// Pedido de reprogramación o cancelación de una sesión futura.
  Future<void> solicitarCambio(Sesion s, {required String participanteId, required String tipo, required String motivo, String? propuesta}) {
    if (tipo != 'REPROGRAMAR' && tipo != 'CANCELAR') throw ErrorDatos(422, 'El tipo debe ser REPROGRAMAR o CANCELAR.');
    return _db.conSesion(s, (tx) async {
      final rep = await _representante(tx, s);
      final r = await consultar(tx, '''
        INSERT INTO agenda.solicitudes_cambio (participante_id, solicitado_por, origen, tipo, motivo, propuesta_inicio)
        SELECT x.id, CAST(@u:text AS uuid), 'FAMILIA', @t:text, @m:text,
               CAST(@pr:text AS timestamp) AT TIME ZONE 'America/Guayaquil'
        FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
        WHERE x.id = CAST(@x:text AS uuid) AND s.inicio > now()
          AND EXISTS (SELECT 1 FROM personas.paciente_representantes pr
                      WHERE pr.paciente_id = x.paciente_id AND pr.representante_id = CAST(@r:text AS uuid))
          AND NOT EXISTS (SELECT 1 FROM agenda.solicitudes_cambio sc WHERE sc.participante_id = x.id AND sc.estado = 'PENDIENTE')''',
          {'u': s.usuarioId, 't': tipo, 'm': motivo, 'pr': propuesta, 'x': participanteId, 'r': rep});
      if (r.affectedRows == 0) {
        throw ErrorDatos(422, 'No se pudo enviar: la sesión ya pasó, no es de tu hijo o ya tiene una solicitud pendiente.');
      }
    });
  }
}
