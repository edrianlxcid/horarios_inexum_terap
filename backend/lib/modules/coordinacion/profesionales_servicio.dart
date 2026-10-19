import 'dart:convert';

import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Profesionales para coordinación: listado con su carga de la semana,
/// ficha con horario y pacientes, y registro de profesionales nuevos.
class ProfesionalesCoordinacion {
  ProfesionalesCoordinacion(this._db);

  final BaseDatos _db;

  static const permisoRegistrar = 'personas.profesionales.registrar';
  static final _cedula = RegExp(r'^[0-9]{10}$');
  static final _correo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _hora = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
  static const _paleta = ['#1D5F8A', '#2E7D32', '#8E24AA', '#C62828', '#EF6C00', '#00838F', '#5D4037', '#3949AB'];

  // Semana actual en hora de Ecuador (lunes 00:00 a domingo 00:00).
  static const _inicioSemana = "date_trunc('week', now() AT TIME ZONE 'America/Guayaquil') AT TIME ZONE 'America/Guayaquil'";
  static const _finSemana = "(date_trunc('week', now() AT TIME ZONE 'America/Guayaquil') + interval '6 days') AT TIME ZONE 'America/Guayaquil'";

  /// Profesionales del alcance con especialidades, sedes, horas de trabajo
  /// a la semana (sin pausas), horas ocupadas esta semana y pacientes del último mes.
  Future<List<Map<String, dynamic>>> lista(Sesion s, {String q = '', String? area, String? sede}) {
    final a = Alcance.de(s, area: area);
    return _db.conSesion(s, (tx) => filas(tx, '''
      SELECT pr.id::text, pr.nombres, pr.apellidos, pr.profesion, pr.color_agenda AS color, pr.telefono, pr.email,
             pr.usuario_id IS NOT NULL AS tiene_cuenta,
             array(SELECT sa.nombre FROM personas.profesional_sub_areas psa JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id
                   WHERE psa.profesional_id = pr.id ORDER BY psa.es_principal DESC, sa.nombre) AS especialidades,
             array(SELECT DISTINCT se.nombre FROM agenda.jornadas j JOIN organizacion.sedes se ON se.id = j.sede_id
                   WHERE j.profesional_id = pr.id AND ${Alcance.jornadaVigente('j')}) AS sedes,
             round(h.horas, 1)::float8 AS horas_semana, o.sesiones AS sesiones_semana, round(o.horas, 1)::float8 AS horas_ocupadas,
             (SELECT count(DISTINCT x.paciente_id)::int FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
              WHERE s.profesional_id = pr.id AND s.estado <> 'CANCELADA' AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')
                AND s.inicio >= now() - interval '30 days') AS pacientes
      FROM personas.profesionales pr
      CROSS JOIN LATERAL (
        SELECT (coalesce(sum(extract(epoch FROM j.hora_fin - j.hora_inicio)), 0)
                - coalesce((SELECT sum(extract(epoch FROM x.hora_fin - x.hora_inicio)) FROM agenda.pausas x
                            WHERE x.profesional_id = pr.id AND x.vigente_desde <= current_date
                              AND coalesce(x.vigente_hasta, 'infinity') >= current_date), 0)) / 3600 AS horas
        FROM agenda.jornadas j WHERE j.profesional_id = pr.id AND j.vigencia @> current_date) h
      CROSS JOIN LATERAL (
        SELECT count(*)::int AS sesiones, coalesce(sum(extract(epoch FROM s.fin - s.inicio)), 0) / 3600 AS horas
        FROM agenda.sesiones s
        WHERE s.profesional_id = pr.id AND s.estado <> 'CANCELADA' AND s.inicio >= $_inicioSemana AND s.inicio < $_finSemana) o
      WHERE pr.activo AND pr.archivado_en IS NULL AND ${Alcance.profesional('pr.id')}
        AND (@sede:text = '' OR EXISTS (SELECT 1 FROM agenda.jornadas j WHERE j.profesional_id = pr.id
                                        AND j.sede_id = CAST(nullif(@sede:text, '') AS uuid) AND ${Alcance.jornadaVigente('j')}))
        AND (@q:text = '' OR lower(pr.nombres || ' ' || pr.apellidos || ' ' || pr.profesion) LIKE lower(@qq:text) OR pr.cedula = @q:text)
      ORDER BY pr.apellidos, pr.nombres''', {...a.parametros, 'sede': sede ?? '', 'q': q.trim(), 'qq': '%${q.trim()}%'}));
  }

  /// Ficha: datos, especialidades, jornadas, pausas, ausencias próximas y
  /// pacientes que atiende (últimos 60 días y sesiones futuras).
  Future<Map<String, Object?>> ficha(Sesion s, String id) {
    final a = Alcance.de(s);
    final p = {...a.parametros, 'id': id};
    return _db.conSesion(s, (tx) async {
      final datos = await fila(tx, '''
        SELECT pr.id::text, pr.cedula, pr.nombres, pr.apellidos, pr.profesion, pr.color_agenda AS color, pr.telefono, pr.email,
               to_char(pr.fecha_ingreso, 'YYYY-MM-DD') AS fecha_ingreso, pr.usuario_id IS NOT NULL AS tiene_cuenta
        FROM personas.profesionales pr
        WHERE pr.id = CAST(@id:text AS uuid) AND ${Alcance.profesional('pr.id')}''', p);
      if (datos == null) throw ErrorDatos(404, 'Ese profesional no está en tu coordinación.');
      return {
        ...datos,
        'especialidades': await filas(tx, '''
          SELECT sa.nombre, ar.nombre AS area, psa.es_principal
          FROM personas.profesional_sub_areas psa
          JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id JOIN catalogo.areas ar ON ar.id = sa.area_id
          WHERE psa.profesional_id = CAST(@id:text AS uuid) ORDER BY psa.es_principal DESC, sa.nombre''', p),
        'jornadas': await filas(tx, '''
          SELECT j.dia_semana AS dia, se.nombre AS sede, to_char(j.hora_inicio, 'HH24:MI') AS inicio,
                 to_char(j.hora_fin, 'HH24:MI') AS fin, to_char(j.vigente_desde, 'YYYY-MM-DD') AS desde
          FROM agenda.jornadas j JOIN organizacion.sedes se ON se.id = j.sede_id
          WHERE j.profesional_id = CAST(@id:text AS uuid) AND ${Alcance.jornadaVigente('j')}
          ORDER BY j.dia_semana, j.hora_inicio''', p),
        'pausas': await filas(tx, '''
          SELECT x.dia_semana AS dia, x.tipo, to_char(x.hora_inicio, 'HH24:MI') AS inicio, to_char(x.hora_fin, 'HH24:MI') AS fin
          FROM agenda.pausas x
          WHERE x.profesional_id = CAST(@id:text AS uuid) AND coalesce(x.vigente_hasta, 'infinity') >= current_date
          ORDER BY x.dia_semana, x.hora_inicio''', p),
        'ausencias': await filas(tx, '''
          SELECT au.tipo, au.motivo,
                 to_char(au.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS desde,
                 to_char(au.fin AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS hasta
          FROM agenda.ausencias au
          WHERE au.profesional_id = CAST(@id:text AS uuid) AND au.fin >= now() ORDER BY au.inicio LIMIT 10''', p),
        'pacientes': await filas(tx, '''
          SELECT pa.id::text, pa.nombres || ' ' || pa.apellidos AS nombre, pa.codigo_historia,
                 string_agg(DISTINCT coalesce(pg.nombre, 'Valoración'), ', ') AS programas,
                 count(*) FILTER (WHERE s.inicio < now())::int AS sesiones_60d,
                 to_char((min(s.inicio) FILTER (WHERE s.inicio >= now())) AT TIME ZONE 'America/Guayaquil',
                         'YYYY-MM-DD"T"HH24:MI') AS proxima
          FROM agenda.participantes x
          JOIN agenda.sesiones s ON s.id = x.sesion_id
          JOIN personas.pacientes pa ON pa.id = x.paciente_id
          LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
          WHERE s.profesional_id = CAST(@id:text AS uuid) AND s.estado <> 'CANCELADA'
            AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA') AND s.inicio >= now() - interval '60 days'
          GROUP BY pa.id ORDER BY 2''', p),
      };
    });
  }

  /// Registra un profesional con sus especialidades, su horario semanal
  /// (jornadas por día y sede) y sus pausas. Todo queda en el alcance del
  /// coordinador; la cuenta de acceso la crea Administración.
  Future<Map<String, Object?>> crear(Sesion s, Map<String, dynamic> d) {
    if (!s.puede(permisoRegistrar)) throw ErrorAcceso(403, 'Tu rol no puede registrar profesionales.');
    final a = Alcance.de(s);
    String? texto(String c) {
      final v = (d[c] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    for (final (c, nombre) in const [('cedula', 'la cédula'), ('nombres', 'los nombres'), ('apellidos', 'los apellidos'),
                                     ('profesion', 'la profesión')]) {
      if (texto(c) == null) throw ErrorDatos(422, 'Falta completar $nombre.');
    }
    if (!_cedula.hasMatch(texto('cedula')!)) throw ErrorDatos(422, 'La cédula debe tener 10 dígitos.');
    final email = texto('email');
    if (email != null && !_correo.hasMatch(email)) throw ErrorDatos(422, 'El correo no es válido.');
    final ingreso = texto('fecha_ingreso');
    if (ingreso != null && DateTime.tryParse(ingreso) == null) throw ErrorDatos(422, 'La fecha de ingreso no es válida.');

    final especialidades = [for (final e in (d['especialidades'] as List?) ?? const []) e.toString()];
    if (especialidades.isEmpty) throw ErrorDatos(422, 'Elige al menos una especialidad.');
    final jornadas = _horarios(d['jornadas'], 'jornada', conSede: true);
    if (jornadas.isEmpty) throw ErrorDatos(422, 'Agrega al menos una jornada de trabajo.');
    final pausas = _horarios(d['pausas'], 'pausa');

    return _db.conSesion(s, (tx) async {
      if (await fila(tx, 'SELECT 1 FROM personas.profesionales WHERE cedula = @c:text', {'c': texto('cedula')}) != null) {
        throw ErrorDatos(409, 'Ya existe un profesional con esa cédula.');
      }
      final validas = await fila(tx, '''
        SELECT count(*)::int AS n FROM catalogo.sub_areas sa
        WHERE sa.activo AND sa.id::text IN (SELECT jsonb_array_elements_text(CAST(@ids:text AS jsonb)))
          AND ${Alcance.area('sa.area_id')}''', {...a.parametros, 'ids': jsonEncode(especialidades)});
      if (validas!['n'] != especialidades.toSet().length) {
        throw ErrorAcceso(403, 'Alguna especialidad no es de las áreas que coordinas.');
      }
      for (final sede in {for (final j in jornadas) j['sede_id']}) {
        if (await fila(tx, 'SELECT 1 WHERE ${Alcance.sede('CAST(@s:text AS uuid)')}', {...a.parametros, 's': sede}) == null) {
          throw ErrorAcceso(403, 'Alguna jornada es en una sede que no coordinas.');
        }
      }
      final cuantos = await fila(tx, 'SELECT count(*)::int AS n FROM personas.profesionales');
      final nuevo = await fila(tx, '''
        INSERT INTO personas.profesionales (cedula, nombres, apellidos, profesion, color_agenda, telefono, email,
                                            fecha_ingreso, creado_por)
        VALUES (@cedula:text, @nombres:text, @apellidos:text, @profesion:text, @color:text, @tel:text, @email:text,
                CAST(@ingreso:text AS date), CAST(@u:text AS uuid))
        RETURNING id::text''', {
        'cedula': texto('cedula'), 'nombres': texto('nombres'), 'apellidos': texto('apellidos'),
        'profesion': texto('profesion'), 'color': _paleta[(cuantos!['n'] as int) % _paleta.length],
        'tel': texto('telefono'), 'email': email, 'ingreso': ingreso, 'u': s.usuarioId,
      });
      final id = nuevo!['id'] as String;
      for (final (i, e) in especialidades.toSet().indexed) {
        await consultar(tx, '''
          INSERT INTO personas.profesional_sub_areas (profesional_id, sub_area_id, es_principal)
          VALUES (CAST(@p:text AS uuid), CAST(@s:text AS uuid), @principal:boolean)''', {'p': id, 's': e, 'principal': i == 0});
      }
      // El horario rige desde hoy o desde la fecha de ingreso, si es posterior.
      const desde = "greatest(current_date, coalesce(CAST(@ingreso:text AS date), current_date))";
      for (final j in jornadas) {
        await consultar(tx, '''
          INSERT INTO agenda.jornadas (profesional_id, sede_id, dia_semana, hora_inicio, hora_fin, vigente_desde)
          VALUES (CAST(@p:text AS uuid), CAST(@sede:text AS uuid), @dia:int4, CAST(@i:text AS time), CAST(@f:text AS time), $desde)''',
            {'p': id, 'sede': j['sede_id'], 'dia': j['dia'], 'i': j['inicio'], 'f': j['fin'], 'ingreso': ingreso});
      }
      for (final x in pausas) {
        await consultar(tx, '''
          INSERT INTO agenda.pausas (profesional_id, dia_semana, hora_inicio, hora_fin, tipo, vigente_desde)
          VALUES (CAST(@p:text AS uuid), @dia:int4, CAST(@i:text AS time), CAST(@f:text AS time), @tipo:text, $desde)''',
            {'p': id, 'dia': x['dia'], 'i': x['inicio'], 'f': x['fin'], 'tipo': x['tipo'] ?? 'ALMUERZO', 'ingreso': ingreso});
      }
      if (await fila(tx, 'SELECT 1 WHERE ${Alcance.profesional('CAST(@id:text AS uuid)')}', {...a.parametros, 'id': id}) == null) {
        throw ErrorAcceso(403, 'Con esas sedes y especialidades el profesional no quedaría en tu coordinación.');
      }
      return {'id': id};
    });
  }

  /// Valida una lista de horarios {dia, inicio, fin[, sede_id][, tipo]}.
  static List<Map<String, dynamic>> _horarios(Object? valor, String nombre, {bool conSede = false}) {
    final lista = [for (final x in (valor as List?) ?? const []) (x as Map).cast<String, dynamic>()];
    for (final x in lista) {
      final dia = x['dia'];
      if (dia is! int || dia < 1 || dia > 6) throw ErrorDatos(422, 'El día de cada $nombre va de lunes (1) a sábado (6).');
      final inicio = '${x['inicio']}', fin = '${x['fin']}';
      if (!_hora.hasMatch(inicio) || !_hora.hasMatch(fin)) throw ErrorDatos(422, 'Las horas de cada $nombre van como HH:MM.');
      if (fin.compareTo(inicio) <= 0) throw ErrorDatos(422, 'En cada $nombre la hora de fin debe ser posterior a la de inicio.');
      if (conSede && '${x['sede_id'] ?? ''}'.isEmpty) throw ErrorDatos(422, 'Cada $nombre necesita su sede.');
      if (!conSede && x['tipo'] != null && !const {'ALMUERZO', 'ADMINISTRATIVA'}.contains(x['tipo'])) {
        throw ErrorDatos(422, 'El tipo de pausa debe ser ALMUERZO o ADMINISTRATIVA.');
      }
    }
    return lista;
  }
}
