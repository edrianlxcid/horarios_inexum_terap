import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Agenda de coordinación: sesiones del día, horario semanal de los
/// profesionales, horas libres, agendar y cancelar.
class AgendaCoordinacion {
  AgendaCoordinacion(this._db);

  final BaseDatos _db;

  /// Sesiones del rango con su ocupación y participantes.
  Future<List<Map<String, dynamic>>> sesiones(Sesion s,
      {required String desde, required String hasta, String? area, String? sede, String? profesional}) {
    final a = Alcance.de(s, area: area);
    return _db.conSesion(s, (tx) => filas(tx, '''
      SELECT s.id::text, to_char(s.inicio AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS inicio,
             to_char(s.fin AT TIME ZONE se.zona_horaria, 'YYYY-MM-DD"T"HH24:MI') AS fin,
             s.tipo, s.estado, s.cupo_maximo, se.nombre AS sede, pr.id::text AS profesional_id,
             pr.nombres || ' ' || pr.apellidos AS terapeuta, pg.nombre AS programa, g.codigo AS grupo,
             coalesce((SELECT json_agg(json_build_object('participante_id', x.id, 'paciente_id', pa.id,
                                'paciente', pa.nombres || ' ' || pa.apellidos, 'asistencia', x.asistencia,
                                'numero_sesion', x.numero_sesion) ORDER BY pa.nombres)
                       FROM agenda.participantes x JOIN personas.pacientes pa ON pa.id = x.paciente_id
                       WHERE x.sesion_id = s.id AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')), '[]'::json) AS participantes
      FROM agenda.sesiones s
      JOIN organizacion.sedes se ON se.id = s.sede_id
      JOIN personas.profesionales pr ON pr.id = s.profesional_id
      LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
      LEFT JOIN agenda.grupos g ON g.id = s.grupo_id
      WHERE (s.inicio AT TIME ZONE se.zona_horaria)::date BETWEEN CAST(@d:text AS date) AND CAST(@h:text AS date)
        AND ${Alcance.sedeYArea('s.sede_id', 'pg.area_id')}
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
                                  'participantes', (SELECT coalesce(json_agg(pa.nombres || ' ' || pa.apellidos ORDER BY pa.nombres), '[]'::json)
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

  /// Horas del día de un terapeuta: libre, ocupada (con cupo), pausa, ausencia o feriado.
  Future<List<Map<String, dynamic>>> disponibilidad(Sesion s, String profesionalId, String fecha) {
    Alcance.de(s);
    return _db.conSesion(s, (tx) => filas(tx, '''
      WITH j AS (
        SELECT j.sede_id, j.hora_inicio, j.hora_fin FROM agenda.jornadas j
        WHERE j.profesional_id = CAST(@p:text AS uuid) AND j.dia_semana = extract(isodow FROM CAST(@f:text AS date))
          AND j.vigencia @> CAST(@f:text AS date)
      ), horas AS (
        SELECT j.sede_id, gs AS hora
        FROM j, generate_series(CAST(@f:text AS date) + j.hora_inicio, CAST(@f:text AS date) + j.hora_fin - interval '1 hour',
                                interval '1 hour') gs
      )
      SELECT to_char(h.hora, 'HH24:MI') AS hora, se.nombre AS sede,
             CASE
               WHEN EXISTS (SELECT 1 FROM organizacion.feriados f WHERE f.fecha = CAST(@f:text AS date)
                            AND (f.sede_id IS NULL OR f.sede_id = h.sede_id)) THEN 'FERIADO'
               WHEN EXISTS (SELECT 1 FROM agenda.pausas pa WHERE pa.profesional_id = CAST(@p:text AS uuid)
                            AND pa.dia_semana = extract(isodow FROM h.hora)
                            AND h.hora::time < pa.hora_fin AND (h.hora + interval '1 hour')::time > pa.hora_inicio) THEN 'PAUSA'
               WHEN EXISTS (SELECT 1 FROM agenda.ausencias au WHERE au.profesional_id = CAST(@p:text AS uuid)
                            AND tstzrange(au.inicio, au.fin) && tstzrange(h.hora AT TIME ZONE se.zona_horaria,
                                                                         (h.hora + interval '1 hour') AT TIME ZONE se.zona_horaria))
                 THEN 'AUSENCIA'
               WHEN s.id IS NOT NULL THEN 'OCUPADO'
               ELSE 'LIBRE'
             END AS estado,
             s.id::text AS sesion_id, pg.nombre AS programa, s.cupo_maximo,
             (SELECT count(*) FROM agenda.participantes x WHERE x.sesion_id = s.id
              AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA'))::int AS ocupados
      FROM horas h
      JOIN organizacion.sedes se ON se.id = h.sede_id
      LEFT JOIN agenda.sesiones s ON s.profesional_id = CAST(@p:text AS uuid) AND s.estado <> 'CANCELADA'
           AND s.rango && tstzrange(h.hora AT TIME ZONE se.zona_horaria, (h.hora + interval '1 hour') AT TIME ZONE se.zona_horaria)
      LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
      ORDER BY h.hora''', {'p': profesionalId, 'f': fecha}));
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
    final p = {
      ...a.parametros,
      'pac': d['paciente_id'], 'prof': d['profesional_id'], 'ini': d['inicio'].toString().replaceFirst('T', ' '),
      'mat': d['matricula_id'] ?? '', 'tipo': tipo, 'u': s.usuarioId,
    };
    return _db.conSesion(s, (tx) async {
      final prog = await fila(tx, tipo == 'VALORACION'
          ? '''SELECT pg.id::text, pg.cupo_maximo, pg.modalidad, pg.duracion_sesion_min, pg.area_id::text
               FROM catalogo.programas pg JOIN catalogo.tipos_programa t ON t.id = pg.tipo_programa_id
               WHERE t.es_valoracion AND pg.activo
                 AND pg.sub_area_requerida_id IN (SELECT sub_area_id FROM personas.profesional_sub_areas
                                                  WHERE profesional_id = CAST(@prof:text AS uuid))
               LIMIT 1'''
          : '''SELECT pg.id::text, pg.cupo_maximo, pg.modalidad, pg.duracion_sesion_min, pg.area_id::text
               FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
               WHERE m.id = CAST(@mat:text AS uuid) AND m.paciente_id = CAST(@pac:text AS uuid)''', p);
      if (prog == null) {
        throw ErrorDatos(422, tipo == 'VALORACION'
            ? 'Ese terapeuta no está habilitado para valoraciones.'
            : 'La matrícula no corresponde al paciente.');
      }
      final sede = await fila(tx, '''
        SELECT j.sede_id::text FROM agenda.jornadas j
        WHERE j.profesional_id = CAST(@prof:text AS uuid)
          AND j.dia_semana = extract(isodow FROM CAST(@ini:text AS timestamp))
          AND j.vigencia @> CAST(@ini:text AS timestamp)::date
        LIMIT 1''', p);
      if (sede == null) throw ErrorDatos(422, 'El terapeuta no trabaja ese día.');
      final enAlcance = await fila(tx, '''
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
        INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id, numero_sesion, creado_por)
        VALUES (CAST(@ses:text AS uuid), CAST(@pac:text AS uuid), CAST(nullif(@mat:text, '') AS uuid),
                (SELECT count(*) + 1 FROM agenda.participantes x
                 JOIN agenda.sesiones xs ON xs.id = x.sesion_id
                 WHERE x.paciente_id = CAST(@pac:text AS uuid)
                   AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA')
                   AND (CASE WHEN @mat:text = '' THEN xs.tipo = 'VALORACION' ELSE x.matricula_id = CAST(nullif(@mat:text, '') AS uuid) END)),
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
          AND ${Alcance.sedeYArea('s.sede_id', 'pg.area_id')}''', {...a.parametros, 'm': motivo, 'u': s.usuarioId, 'id': sesionId});
      if (r.affectedRows == 0) throw ErrorDatos(404, 'La sesión no existe, ya no está programada o no es de tu coordinación.');
      await consultar(tx, '''
        UPDATE agenda.participantes SET asistencia = 'CANCELADA'
        WHERE sesion_id = CAST(@id:text AS uuid) AND asistencia = 'PENDIENTE' ''', {'id': sesionId});
    });
  }
}
