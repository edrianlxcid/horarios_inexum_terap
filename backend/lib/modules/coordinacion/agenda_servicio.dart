import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Agenda de coordinación: sesiones del día, horario semanal de los
/// profesionales, horas libres, agendar y cancelar.
class AgendaCoordinacion {
  AgendaCoordinacion(this._db);

  final BaseDatos _db;

  /// Lo que Coordinación ve de cada estudiante en una cita, como en sus
  /// horarios: contrato, nombre, edad, fase y observación.
  static String _participante(String x, String pa) => '''
    json_build_object('participante_id', $x.id, 'paciente_id', $pa.id, 'paciente', $pa.nombres || ' ' || $pa.apellidos,
      'asistencia', $x.asistencia, 'numero_sesion', $x.numero_sesion, 'observacion', $x.observacion,
      'edad_meses', (extract(year FROM age($pa.fecha_nacimiento)) * 12 + extract(month FROM age($pa.fecha_nacimiento)))::int,
      'contrato', (SELECT c.codigo FROM matriculas.matriculas m JOIN matriculas.contratos c ON c.id = m.contrato_id
                   WHERE m.id = $x.matricula_id),
      'fase', coalesce((SELECT f.nombre FROM catalogo.programa_fases f WHERE f.id = $x.fase_id),
                       (SELECT f.nombre FROM matriculas.matriculas m JOIN catalogo.programa_fases f ON f.id = m.fase_actual_id
                        WHERE m.id = $x.matricula_id)))''';

  /// Sesiones del rango con su ocupación y participantes.
  Future<List<Map<String, dynamic>>> sesiones(Sesion s,
      {required String desde, required String hasta, String? area, String? sede, String? profesional}) {
    final a = Alcance.de(s, area: area);
    return _db.conSesion(s, (tx) => filas(tx, '''
      SELECT s.id::text, to_char(s.inicio AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS inicio,
             to_char(s.fin AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS fin,
             s.tipo, s.estado, s.cupo_maximo, se.nombre AS sede, pr.id::text AS profesional_id,
             pr.nombres || ' ' || pr.apellidos AS terapeuta, pg.nombre AS programa, g.codigo AS grupo,
             coalesce((SELECT json_agg(${_participante('x', 'pa')} ORDER BY pa.nombres)
                       FROM agenda.participantes x JOIN personas.pacientes pa ON pa.id = x.paciente_id
                       WHERE x.sesion_id = s.id AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')), '[]'::json) AS participantes
      FROM agenda.sesiones s
      JOIN organizacion.sedes se ON se.id = s.sede_id
      JOIN personas.profesionales pr ON pr.id = s.profesional_id
      LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
      LEFT JOIN agenda.grupos g ON g.id = s.grupo_id
      WHERE (s.inicio AT TIME ZONE se.zona_horaria)::date BETWEEN CAST(@d:text AS date) AND CAST(@h:text AS date)
        AND ((${Alcance.sedeYArea('s.sede_id', 'pg.area_id')})
             -- Valoraciones de sus estudiantes aunque sean del área de Neuro (caso excepcional de Estimulación temprana).
             OR (s.tipo = 'VALORACION' AND ${Alcance.sede('s.sede_id')}
                 AND EXISTS (SELECT 1 FROM agenda.participantes vx JOIN personas.pacientes vp ON vp.id = vx.paciente_id
                             WHERE vx.sesion_id = s.id AND ${Alcance.paciente('vp')})))
        AND (@sede:text = '' OR s.sede_id = CAST(nullif(@sede:text, '') AS uuid))
        AND (@prof:text = '' OR s.profesional_id = CAST(nullif(@prof:text, '') AS uuid))
      ORDER BY s.inicio, terapeuta''', {...a.parametros, 'd': desde, 'h': hasta, 'sede': sede ?? '', 'prof': profesional ?? ''}));
  }

  /// Horario de la semana (lunes a sábado) de cada profesional del alcance:
  /// jornadas, pausas, ausencias y sesiones, más los feriados de la semana.
  Future<Map<String, Object?>> semana(Sesion s, {required String fecha, String? area, String? sede, String? profesional}) {
    final a = Alcance.de(s, area: area);
    return _db.conSesion(s, (tx) async {
      final rango = await fila(tx, '''
        SELECT to_char(date_trunc('week', CAST(@f:text AS date)), 'YYYY-MM-DD') AS desde,
               to_char(date_trunc('week', CAST(@f:text AS date)) + interval '5 days', 'YYYY-MM-DD') AS hasta''', {'f': fecha});
      final p = {...a.parametros, 'd': rango!['desde'], 'h': rango['hasta'], 'sede': sede ?? '', 'prof': profesional ?? ''};
      const desdeTz = "CAST(@d:text AS timestamp) AT TIME ZONE 'America/Guayaquil'";
      const hastaTz = "(CAST(@h:text AS timestamp) + interval '1 day') AT TIME ZONE 'America/Guayaquil'";
      final profesionales = await filas(tx, '''
        SELECT pr.id::text, pr.nombres || ' ' || pr.apellidos AS nombre, pr.profesion, pr.color_agenda AS color,
               agenda.minutos_turno(pr.id) AS minutos_turno,
               coalesce((SELECT json_agg(json_build_object('dia', j.dia_semana, 'sede', se.nombre,
                                  'inicio', to_char(j.hora_inicio, 'HH24:MI'), 'fin', to_char(j.hora_fin, 'HH24:MI'))
                                  ORDER BY j.dia_semana, j.hora_inicio)
                         FROM agenda.jornadas j JOIN organizacion.sedes se ON se.id = j.sede_id
                         WHERE j.profesional_id = pr.id
                           AND j.vigencia && daterange(CAST(@d:text AS date), CAST(@h:text AS date), '[]')), '[]'::json) AS jornadas,
               coalesce((SELECT json_agg(json_build_object('dia', x.dia_semana, 'tipo', x.tipo,
                                  'inicio', to_char(x.hora_inicio, 'HH24:MI'), 'fin', to_char(x.hora_fin, 'HH24:MI'))
                                  ORDER BY x.dia_semana, x.hora_inicio)
                         FROM agenda.pausas x
                         WHERE x.profesional_id = pr.id AND x.vigente_desde <= CAST(@h:text AS date)
                           AND coalesce(x.vigente_hasta, 'infinity') >= CAST(@d:text AS date)), '[]'::json) AS pausas,
               coalesce((SELECT json_agg(json_build_object('tipo', au.tipo,
                                  'desde', to_char(au.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI'),
                                  'hasta', to_char(au.fin AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI'))
                                  ORDER BY au.inicio)
                         FROM agenda.ausencias au
                         WHERE au.profesional_id = pr.id AND tstzrange(au.inicio, au.fin) && tstzrange($desdeTz, $hastaTz)),
                        '[]'::json) AS ausencias,
               coalesce((SELECT json_agg(json_build_object('id', ss.id, 'tipo', ss.tipo, 'estado', ss.estado,
                                  'fecha', to_char(ss.inicio AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD'),
                                  'inicio', to_char(ss.inicio AT TIME ZONE se.zona_horaria, 'HH24:MI'),
                                  'fin', to_char(ss.fin AT TIME ZONE se.zona_horaria, 'HH24:MI'),
                                  'programa', pg.nombre, 'grupo', g.codigo, 'sede', se.nombre, 'cupo', ss.cupo_maximo,
                                  'participantes', (SELECT coalesce(json_agg(${_participante('x', 'pa')} ORDER BY pa.nombres), '[]'::json)
                                                    FROM agenda.participantes x JOIN personas.pacientes pa ON pa.id = x.paciente_id
                                                    WHERE x.sesion_id = ss.id AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')))
                                  ORDER BY ss.inicio)
                         FROM agenda.sesiones ss
                         JOIN organizacion.sedes se ON se.id = ss.sede_id
                         LEFT JOIN catalogo.programas pg ON pg.id = ss.programa_id
                         LEFT JOIN agenda.grupos g ON g.id = ss.grupo_id
                         WHERE ss.profesional_id = pr.id AND ss.estado <> 'CANCELADA'
                           AND ss.inicio >= $desdeTz AND ss.inicio < $hastaTz), '[]'::json) AS sesiones
        FROM personas.profesionales pr
        WHERE pr.activo AND pr.archivado_en IS NULL AND ${Alcance.profesional('pr.id')}
          AND (@sede:text = '' OR EXISTS (SELECT 1 FROM agenda.jornadas j WHERE j.profesional_id = pr.id
                                          AND j.sede_id = CAST(nullif(@sede:text, '') AS uuid)))
          AND (@prof:text = '' OR pr.id = CAST(nullif(@prof:text, '') AS uuid))
        ORDER BY pr.apellidos, pr.nombres''', p);
      final feriados = await filas(tx, '''
        SELECT to_char(f.fecha, 'YYYY-MM-DD') AS fecha, f.nombre, se.nombre AS sede
        FROM organizacion.feriados f LEFT JOIN organizacion.sedes se ON se.id = f.sede_id
        WHERE f.fecha BETWEEN CAST(@d:text AS date) AND CAST(@h:text AS date)
        ORDER BY f.fecha''', p);
      return {'desde': rango['desde'], 'hasta': rango['hasta'], 'feriados': feriados, 'profesionales': profesionales};
    });
  }

  /// Turnos del día de un terapeuta: libre, ocupado (con cupo), ausencia o
  /// feriado, más sus pausas. Los turnos duran lo que marca su especialidad
  /// (60 minutos en Neuro, 45 seguidos en Terapia de lenguaje) y se cuentan
  /// desde el inicio de la jornada y otra vez después de cada pausa.
  Future<List<Map<String, dynamic>>> disponibilidad(Sesion s, String profesionalId, String fecha) {
    Alcance.de(s);
    return _db.conSesion(s, (tx) => filas(tx, '''
      WITH turno AS (SELECT make_interval(mins => agenda.minutos_turno(CAST(@p:text AS uuid))) AS t),
      j AS (
        SELECT j.sede_id, tsrange(CAST(@f:text AS date) + j.hora_inicio, CAST(@f:text AS date) + j.hora_fin) AS r
        FROM agenda.jornadas j
        WHERE j.profesional_id = CAST(@p:text AS uuid) AND j.dia_semana = extract(isodow FROM CAST(@f:text AS date))
          AND j.vigencia @> CAST(@f:text AS date)
      ), p AS (
        SELECT pa.tipo, tsrange(CAST(@f:text AS date) + pa.hora_inicio, CAST(@f:text AS date) + pa.hora_fin) AS r
        FROM agenda.pausas pa
        WHERE pa.profesional_id = CAST(@p:text AS uuid) AND pa.dia_semana = extract(isodow FROM CAST(@f:text AS date))
          AND pa.vigente_desde <= CAST(@f:text AS date) AND coalesce(pa.vigente_hasta, 'infinity') >= CAST(@f:text AS date)
      ), tramos AS (
        -- La jornada sin sus pausas: cada tramo se divide en turnos.
        SELECT j.sede_id, unnest(tsmultirange(j.r) - coalesce((SELECT range_agg(p.r) FROM p), '{}'::tsmultirange)) AS r
        FROM j
      ), franjas AS (
        SELECT tr.sede_id, gs AS ini, gs + tu.t AS fin, NULL::text AS pausa
        FROM tramos tr, turno tu, generate_series(lower(tr.r), upper(tr.r) - tu.t, tu.t) gs
        UNION ALL
        SELECT j.sede_id, lower(p.r), upper(p.r), p.tipo FROM p JOIN j ON j.r && p.r
      )
      SELECT to_char(fr.ini, 'HH24:MI') AS hora, to_char(fr.fin, 'HH24:MI') AS fin, se.nombre AS sede,
             CASE
               WHEN fr.pausa IS NOT NULL THEN 'PAUSA'
               WHEN EXISTS (SELECT 1 FROM organizacion.feriados f WHERE f.fecha = CAST(@f:text AS date)
                            AND (f.sede_id IS NULL OR f.sede_id = fr.sede_id)) THEN 'FERIADO'
               WHEN EXISTS (SELECT 1 FROM agenda.ausencias au WHERE au.profesional_id = CAST(@p:text AS uuid)
                            AND tstzrange(au.inicio, au.fin) && tstzrange(fr.ini AT TIME ZONE se.zona_horaria,
                                                                         fr.fin AT TIME ZONE se.zona_horaria))
                 THEN 'AUSENCIA'
               WHEN s.id IS NOT NULL THEN 'OCUPADO'
               ELSE 'LIBRE'
             END AS estado,
             fr.pausa, s.id::text AS sesion_id, pg.nombre AS programa, s.cupo_maximo,
             (SELECT count(*) FROM agenda.participantes x WHERE x.sesion_id = s.id
              AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA'))::int AS ocupados
      FROM franjas fr
      JOIN organizacion.sedes se ON se.id = fr.sede_id
      LEFT JOIN LATERAL (
        SELECT x.* FROM agenda.sesiones x
        WHERE fr.pausa IS NULL AND x.profesional_id = CAST(@p:text AS uuid) AND x.estado <> 'CANCELADA'
          AND x.rango && tstzrange(fr.ini AT TIME ZONE se.zona_horaria, fr.fin AT TIME ZONE se.zona_horaria)
        ORDER BY x.inicio LIMIT 1) s ON true
      LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
      ORDER BY fr.ini''', {'p': profesionalId, 'f': fecha}));
  }

  /// Nota de coordinación de una cita ("desde el 12 de octubre", "no mover"...).
  Future<void> observacion(Sesion s, String participanteId, String? texto) {
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async {
      final r = await consultar(tx, '''
        UPDATE agenda.participantes x SET observacion = nullif(trim(@t:text), ''), actualizado_por = CAST(@u:text AS uuid)
        FROM agenda.sesiones ss, personas.pacientes pa
        WHERE x.id = CAST(@id:text AS uuid) AND ss.id = x.sesion_id AND pa.id = x.paciente_id
          AND ${Alcance.sede('ss.sede_id')} AND ${Alcance.paciente('pa')}''',
          {...a.parametros, 't': texto ?? '', 'u': s.usuarioId, 'id': participanteId});
      if (r.affectedRows == 0) throw ErrorDatos(404, 'Esa cita no existe o no es de tu coordinación.');
    });
  }

  /// Agenda a un paciente con un terapeuta a una hora. Si el terapeuta ya
  /// tiene una sesión grupal del mismo programa a esa hora, lo suma a ella.
  /// Todas las reglas (jornada, feriados, cupo, choques, saldo) las valida la base.
  Future<Map<String, Object?>> agendar(Sesion s, Map<String, dynamic> d) {
    final a = Alcance.de(s);
    final tipo = d['tipo'] as String? ?? 'PROGRAMA';
    if (!const {'VALORACION', 'PROGRAMA', 'REPOSICION'}.contains(tipo)) {
      throw ErrorDatos(422, 'El tipo debe ser VALORACION, PROGRAMA o REPOSICION.');
    }
    for (final c in ['paciente_id', 'profesional_id', 'inicio']) {
      if ((d[c] ?? '').toString().isEmpty) throw ErrorDatos(422, 'Falta completar "$c".');
    }
    if (tipo != 'VALORACION' && (d['matricula_id'] ?? '').toString().isEmpty) {
      throw ErrorDatos(422, 'Para una sesión de programa elige la matrícula del paciente.');
    }
    final p = <String, Object?>{
      ...a.parametros,
      'pac': d['paciente_id'], 'prof': d['profesional_id'], 'ini': d['inicio'].toString().replaceFirst('T', ' '),
      'mat': d['matricula_id'] ?? '', 'tipo': tipo, 'u': s.usuarioId, 'obs': d['observacion'] as String? ?? '',
    };
    return _db.conSesion(s, (tx) async {
      final paciente = await fila(tx, 'SELECT 1 FROM personas.pacientes pa WHERE pa.id = CAST(@pac:text AS uuid) AND ${Alcance.paciente('pa')}', p);
      if (paciente == null) throw ErrorDatos(404, 'Ese estudiante no está en tu coordinación.');

      // Una sesión de valoración pertenece a la valoración en curso del
      // estudiante (la final antes que la inicial) y a una de sus especialidades
      // previstas: la elegida o la primera que tenga el profesional.
      if (tipo == 'VALORACION') {
        final pv = await fila(tx, '''
          SELECT pv.id::text, pv.tipo FROM agenda.procesos_valoracion pv
          WHERE pv.paciente_id = CAST(@pac:text AS uuid) AND pv.estado = 'EN_CURSO'
            AND (@proc:text = '' OR pv.id = CAST(nullif(@proc:text, '') AS uuid))
          ORDER BY pv.tipo = 'FINAL' DESC LIMIT 1''', {...p, 'proc': d['proceso_id'] ?? ''});
        if (pv == null) {
          throw ErrorDatos(422, 'Primero abre la valoración del estudiante (especialidades y sesiones previstas) desde su ficha.');
        }
        final esp = await fila(tx, '''
          SELECT pe.sub_area_id::text FROM agenda.proceso_especialidades pe
          JOIN personas.profesional_sub_areas psa ON psa.sub_area_id = pe.sub_area_id AND psa.profesional_id = CAST(@prof:text AS uuid)
          WHERE pe.proceso_id = CAST(@proc:text AS uuid) AND (@esp:text = '' OR pe.sub_area_id = CAST(nullif(@esp:text, '') AS uuid))
          ORDER BY psa.es_principal DESC LIMIT 1''', {...p, 'proc': pv['id'], 'esp': d['especialidad_id'] ?? ''});
        if (esp == null) throw ErrorDatos(422, 'Ese profesional no es de ninguna especialidad prevista en la valoración.');
        p['proc'] = pv['id'];
        p['esp'] = esp['sub_area_id'];
        p['vt'] = pv['tipo'];
      } else {
        p['proc'] = '';
        p['esp'] = '';
      }
      final prog = await fila(tx, tipo == 'VALORACION'
          ? '''SELECT pg.id::text, pg.cupo_maximo, pg.modalidad, pg.duracion_sesion_min, pg.area_id::text
               FROM catalogo.programas pg
               WHERE pg.activo AND pg.valoracion = @vt:text
                 AND (pg.sub_area_requerida_id = CAST(@esp:text AS uuid)
                      OR EXISTS (SELECT 1 FROM catalogo.programa_especialidades pe
                                 WHERE pe.programa_id = pg.id AND pe.sub_area_id = CAST(@esp:text AS uuid)))
               LIMIT 1'''
          : '''SELECT pg.id::text, pg.cupo_maximo, pg.modalidad, pg.duracion_sesion_min, pg.area_id::text,
                      pg.requiere_valoracion AND NOT EXISTS (
                        SELECT 1 FROM agenda.procesos_valoracion pv
                        WHERE pv.paciente_id = m.paciente_id AND pv.estado = 'COMPLETADA'
                          AND pv.resultado IN ('INGRESA_A_PROGRAMA', 'CONTINUA')) AS falta_valoracion
               FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
               WHERE m.id = CAST(@mat:text AS uuid) AND m.paciente_id = CAST(@pac:text AS uuid)''', p);
      if (prog == null) {
        throw ErrorDatos(422, tipo == 'VALORACION'
            ? 'No hay un programa de valoración para esa especialidad.'
            : 'La matrícula no corresponde al paciente.');
      }
      if (prog['falta_valoracion'] == true) {
        throw ErrorDatos(422, 'Este estudiante aún no termina su valoración: el programa empieza cuando se cierra la valoración inicial.');
      }
      final sede = await fila(tx, '''
        SELECT j.sede_id::text FROM agenda.jornadas j
        WHERE j.profesional_id = CAST(@prof:text AS uuid)
          AND j.dia_semana = extract(isodow FROM CAST(@ini:text AS timestamp))
          AND j.vigencia @> CAST(@ini:text AS timestamp)::date
        LIMIT 1''', p);
      if (sede == null) throw ErrorDatos(422, 'El terapeuta no trabaja ese día.');
      // Las valoraciones son de Neuro, pero también se valora (como excepción) a
      // estudiantes de Estimulación temprana: para ellas basta con que la sede
      // sea del coordinador. Lo demás debe ser de su sede y de su área.
      final enAlcance = await fila(tx, tipo == 'VALORACION'
          ? 'SELECT 1 WHERE ${Alcance.sede('CAST(@sede:text AS uuid)')}'
          : '''
        SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
        WHERE (a.sede IS NULL OR a.sede = CAST(@sede:text AS uuid)) AND (a.area IS NULL OR a.area = CAST(@area_p:text AS uuid))''',
          {...p, 'sede': sede['sede_id'], 'area_p': prog['area_id']});
      if (enAlcance == null) throw ErrorAcceso(403, 'Esa sede o ese programa no están en tu coordinación.');

      final grupal = prog['modalidad'] != 'INDIVIDUAL';
      final q = {...p, 'prog': prog['id'], 'sede': sede['sede_id'], 'cupo': grupal ? prog['cupo_maximo'] : 1,
                 'dur': prog['duracion_sesion_min'].toString()};
      var sesion = await fila(tx, '''
        SELECT id::text, programa_id::text FROM agenda.sesiones
        WHERE profesional_id = CAST(@prof:text AS uuid) AND estado <> 'CANCELADA'
          AND inicio = CAST(@ini:text AS timestamp) AT TIME ZONE 'America/Guayaquil' ''', q);
      if (sesion != null && (!grupal || sesion['programa_id'] != prog['id'])) {
        throw ErrorDatos(422, 'El terapeuta ya tiene otra sesión a esa hora.');
      }
      sesion ??= await fila(tx, '''
        INSERT INTO agenda.sesiones (sede_id, profesional_id, programa_id, tipo, inicio, fin, cupo_maximo, creado_por)
        VALUES (CAST(@sede:text AS uuid), CAST(@prof:text AS uuid), CAST(@prog:text AS uuid), @tipo:text,
                CAST(@ini:text AS timestamp) AT TIME ZONE 'America/Guayaquil',
                (CAST(@ini:text AS timestamp) + CAST(@dur:text || ' minutes' AS interval)) AT TIME ZONE 'America/Guayaquil',
                @cupo:int4, CAST(@u:text AS uuid))
        RETURNING id::text, programa_id::text''', q);
      final participante = await fila(tx, '''
        INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id, proceso_valoracion_id, valoracion_especialidad_id,
                                          observacion, numero_sesion, creado_por)
        VALUES (CAST(@ses:text AS uuid), CAST(@pac:text AS uuid), CAST(nullif(@mat:text, '') AS uuid),
                CAST(nullif(@proc:text, '') AS uuid), CAST(nullif(@esp:text, '') AS uuid), nullif(trim(@obs:text), ''),
                -- Número de sesión dentro de la matrícula o de la valoración.
                (SELECT count(*) + 1 FROM agenda.participantes x
                 WHERE x.paciente_id = CAST(@pac:text AS uuid)
                   AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA')
                   AND (CASE WHEN @proc:text <> '' THEN x.proceso_valoracion_id = CAST(nullif(@proc:text, '') AS uuid)
                             ELSE x.matricula_id = CAST(nullif(@mat:text, '') AS uuid) END)),
                CAST(@u:text AS uuid))
        RETURNING id::text, numero_sesion''', {...q, 'ses': sesion!['id']});
      return {'sesion_id': sesion['id'], 'participante_id': participante!['id'], 'numero_sesion': participante['numero_sesion']};
    });
  }

  Future<void> cancelar(Sesion s, String sesionId, String motivo) {
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async {
      final r = await consultar(tx, '''
        UPDATE agenda.sesiones s SET estado = 'CANCELADA', motivo_cancelacion = @m:text, actualizado_por = CAST(@u:text AS uuid)
        FROM catalogo.programas pg
        WHERE s.id = CAST(@id:text AS uuid) AND s.estado = 'PROGRAMADA' AND pg.id = s.programa_id
          AND ((s.tipo = 'VALORACION' AND ${Alcance.sede('s.sede_id')}) OR (${Alcance.sedeYArea('s.sede_id', 'pg.area_id')}))''',
          {...a.parametros, 'm': motivo, 'u': s.usuarioId, 'id': sesionId});
      if (r.affectedRows == 0) throw ErrorDatos(404, 'La sesión no existe, ya no está programada o no es de tu coordinación.');
      await consultar(tx, '''
        UPDATE agenda.participantes SET asistencia = 'CANCELADA'
        WHERE sesion_id = CAST(@id:text AS uuid) AND asistencia = 'PENDIENTE' ''', {'id': sesionId});
    });
  }
}
