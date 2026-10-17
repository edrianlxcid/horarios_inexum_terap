import 'dart:convert';

import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Coordinación: agenda, pacientes y solicitudes, limitados a las sedes y
/// áreas asignadas al coordinador (un coordinador de Neuro no ve Estimulación).
class CoordinacionServicio {
  CoordinacionServicio(this._db, this._llave);

  final BaseDatos _db;
  final String _llave;

  /// Alcance del coordinador como JSON para la consulta, opcionalmente
  /// reducido a un área elegida en la pantalla ("cambiar de interfaz").
  Map<String, Object?> _alcance(Sesion s, {String? area}) {
    final pares = s.alcance('COORDINADOR');
    if (pares.isEmpty) throw ErrorAcceso(403, 'Necesitas el rol de coordinación.');
    if (area != null && area.isNotEmpty && !pares.any((p) => p['area'] == null || p['area'] == area)) {
      throw ErrorAcceso(403, 'No coordinas esa área.');
    }
    return {'alcance': jsonEncode(pares), 'area': area ?? ''};
  }

  /// Condición SQL: la sede y el área caen dentro del alcance.
  static String _enAlcance(String sede, String area) => '''
    EXISTS (SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
            WHERE (a.sede IS NULL OR a.sede = $sede) AND (a.area IS NULL OR a.area = $area))
    AND (@area:text = '' OR $area = CAST(nullif(@area:text, '') AS uuid))''';

  /// Sedes, áreas, terapeutas, programas y niveles de demanda para los filtros.
  Future<Map<String, Object?>> contexto(Sesion s) {
    final a = _alcance(s);
    return _db.conSesion(s, (tx) async => {
          'alcance': s.alcance('COORDINADOR'),
          'sedes': await filas(tx, '''
            SELECT se.id::text, se.nombre FROM organizacion.sedes se
            WHERE se.activo AND EXISTS (SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
                                        WHERE a.sede IS NULL OR a.sede = se.id)
            ORDER BY se.nombre''', a),
          'areas': await filas(tx, '''
            SELECT ar.id::text, ar.nombre FROM catalogo.areas ar
            WHERE ar.activo AND EXISTS (SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
                                        WHERE a.area IS NULL OR a.area = ar.id)
            ORDER BY ar.nombre''', a),
          'terapeutas': await filas(tx, '''
            SELECT pr.id::text, pr.nombres || ' ' || pr.apellidos AS nombre, pr.profesion,
                   (SELECT j.sede_id::text FROM agenda.jornadas j WHERE j.profesional_id = pr.id LIMIT 1) AS sede_id,
                   array(SELECT DISTINCT sa.area_id::text FROM personas.profesional_sub_areas psa
                         JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id WHERE psa.profesional_id = pr.id) AS areas
            FROM personas.profesionales pr
            WHERE pr.activo AND pr.archivado_en IS NULL
              AND EXISTS (SELECT 1 FROM agenda.jornadas j
                          JOIN personas.profesional_sub_areas psa ON psa.profesional_id = j.profesional_id
                          JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id
                          WHERE j.profesional_id = pr.id AND ${_enAlcance('j.sede_id', 'sa.area_id')})
            ORDER BY 2''', a),
          'programas': await filas(tx, '''
            SELECT pg.id::text, pg.nombre, pg.area_id::text, pg.modalidad, pg.cupo_maximo, t.es_valoracion
            FROM catalogo.programas pg JOIN catalogo.tipos_programa t ON t.id = pg.tipo_programa_id
            WHERE pg.activo ORDER BY pg.nombre'''),
          'niveles_demanda': await filas(tx, 'SELECT id::text, nombre, peso FROM personas.niveles_demanda ORDER BY orden'),
        });
  }

  /// Sesiones del rango con su ocupación y participantes.
  Future<List<Map<String, dynamic>>> agenda(Sesion s, {required String desde, required String hasta, String? area, String? sede, String? profesional}) {
    final a = _alcance(s, area: area);
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
        AND ${_enAlcance('s.sede_id', 'pg.area_id')}
        AND (@sede:text = '' OR s.sede_id = CAST(nullif(@sede:text, '') AS uuid))
        AND (@prof:text = '' OR s.profesional_id = CAST(nullif(@prof:text, '') AS uuid))
      ORDER BY s.inicio, terapeuta''', {...a, 'd': desde, 'h': hasta, 'sede': sede ?? '', 'prof': profesional ?? ''}));
  }

  /// Horas del día de un terapeuta: libre, ocupada (con cupo), pausa, ausencia o feriado.
  Future<List<Map<String, dynamic>>> disponibilidad(Sesion s, String profesionalId, String fecha) {
    _alcance(s);
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

  Future<Map<String, Object?>> pacientes(Sesion s, {String q = '', String? area, String? estado, int pagina = 1}) {
    final a = _alcance(s, area: area);
    final p = {...a, 'q': q.trim(), 'qq': '%${q.trim()}%', 'estado': estado ?? '', 'llave': _llave, 'desde': (pagina - 1) * 25};
    const filtro = '''
      FROM personas.pacientes pa
      JOIN organizacion.sedes se ON se.id = pa.sede_principal_id
      WHERE pa.archivado_en IS NULL
        AND EXISTS (SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
                    WHERE a.sede IS NULL OR a.sede = pa.sede_principal_id)
        AND (@area:text = '' OR EXISTS (SELECT 1 FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
                                        WHERE m.paciente_id = pa.id AND pg.area_id = CAST(nullif(@area:text, '') AS uuid)))
        AND (@estado:text = '' OR pa.estado = @estado:text)
        AND (@q:text = '' OR lower(pa.nombres || ' ' || pa.apellidos) LIKE lower(@qq:text) OR pa.codigo_historia ILIKE @qq:text
             OR pa.cedula_huella = comun.huella(@q:text, @llave:text))''';
    return _db.conSesion(s, (tx) async {
      final total = await fila(tx, 'SELECT count(*)::int AS n $filtro', p);
      final lista = await filas(tx, '''
        SELECT pa.id::text, pa.codigo_historia, pa.nombres, pa.apellidos, pa.estado, se.nombre AS sede,
               (extract(year FROM age(pa.fecha_nacimiento)) * 12 + extract(month FROM age(pa.fecha_nacimiento)))::int AS edad_meses,
               (SELECT string_agg(pg.nombre, ', ') FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
                WHERE m.paciente_id = pa.id AND m.estado IN ('EN_CURSO', 'CONGELADA')) AS programas
        $filtro ORDER BY pa.apellidos, pa.nombres LIMIT 25 OFFSET @desde:int4''', p);
      return {'total': total!['n'], 'pagina': pagina, 'tamano': 25, 'filas': lista};
    });
  }

  Future<Map<String, Object?>> paciente(Sesion s, String pacienteId) {
    final a = _alcance(s);
    final p = {...a, 'id': pacienteId, 'llave': _llave};
    return _db.conSesion(s, (tx) async {
      final datos = await fila(tx, '''
        SELECT pa.id::text, pa.codigo_historia, pa.nombres, pa.apellidos, comun.descifrar(pa.cedula, @llave:text) AS cedula,
               to_char(pa.fecha_nacimiento, 'YYYY-MM-DD') AS fecha_nacimiento, pa.sexo, pa.direccion, pa.estado,
               pa.sede_principal_id::text AS sede_id, se.nombre AS sede, pa.observaciones,
               nd.nombre AS demanda, cd.motivo AS motivo_demanda
        FROM personas.pacientes pa
        JOIN organizacion.sedes se ON se.id = pa.sede_principal_id
        LEFT JOIN personas.clasificaciones_demanda cd ON cd.paciente_id = pa.id AND cd.vigente
        LEFT JOIN personas.niveles_demanda nd ON nd.id = cd.nivel_id
        WHERE pa.id = CAST(@id:text AS uuid)
          AND EXISTS (SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
                      WHERE a.sede IS NULL OR a.sede = pa.sede_principal_id)''', p);
      if (datos == null) throw ErrorDatos(404, 'Ese paciente no está en tus sedes.');
      await consultar(tx, "SELECT seguridad.registrar_lectura('personas.pacientes', @id:text)", p);
      return {
        ...datos,
        'representantes': await filas(tx, '''
          SELECT r.id::text, r.nombres, r.apellidos, r.cedula, r.telefono, r.email, pr.parentesco, pr.es_principal,
                 r.usuario_id IS NOT NULL AS tiene_cuenta
          FROM personas.paciente_representantes pr JOIN personas.representantes r ON r.id = pr.representante_id
          WHERE pr.paciente_id = CAST(@id:text AS uuid) ORDER BY pr.es_principal DESC''', p),
        'matriculas': await filas(tx, '''
          SELECT v.matricula_id::text AS id, pg.id::text AS programa_id, pg.nombre AS programa, pg.area_id::text AS area_id,
                 v.estado, c.codigo AS contrato, v.sesiones_contratadas::int AS contratadas,
                 v.sesiones_consumidas::int AS realizadas, v.sesiones_agendadas::int AS agendadas,
                 v.sesiones_por_agendar::int AS por_agendar, f.nombre AS fase,
                 to_char(m.fecha_inicio, 'YYYY-MM-DD') AS inicio, to_char(m.fecha_fin_estimada, 'YYYY-MM-DD') AS fin
          FROM matriculas.v_saldo_sesiones v
          JOIN matriculas.matriculas m ON m.id = v.matricula_id
          JOIN matriculas.contratos c ON c.id = m.contrato_id
          JOIN catalogo.programas pg ON pg.id = v.programa_id
          LEFT JOIN catalogo.programa_fases f ON f.id = m.fase_actual_id
          WHERE v.paciente_id = CAST(@id:text AS uuid) ORDER BY m.fecha_inicio DESC''', p),
        'proximas_sesiones': await filas(tx, '''
          SELECT x.id::text AS participante_id, s.id::text AS sesion_id,
                 to_char(s.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS inicio,
                 s.tipo, pg.nombre AS programa, pr.nombres || ' ' || pr.apellidos AS terapeuta, x.numero_sesion
          FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
          JOIN personas.profesionales pr ON pr.id = s.profesional_id
          LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
          WHERE x.paciente_id = CAST(@id:text AS uuid) AND s.inicio >= now() AND s.estado <> 'CANCELADA'
            AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')
          ORDER BY s.inicio LIMIT 10''', p),
      };
    });
  }

  /// Registra un paciente nuevo y su representante principal (o lo vincula si ya existe).
  Future<Map<String, Object?>> crearPaciente(Sesion s, Map<String, dynamic> d) {
    final a = _alcance(s);
    final rep = (d['representante'] as Map?)?.cast<String, dynamic>();
    if (rep == null) throw ErrorDatos(422, 'Falta el representante.');
    for (final c in ['nombres', 'apellidos', 'fecha_nacimiento', 'sede_id']) {
      if ((d[c] ?? '').toString().trim().isEmpty) throw ErrorDatos(422, 'Falta completar "$c".');
    }
    for (final c in ['cedula', 'nombres', 'apellidos', 'parentesco']) {
      if ((rep[c] ?? '').toString().trim().isEmpty) throw ErrorDatos(422, 'Falta completar "$c" del representante.');
    }
    return _db.conSesion(s, (tx) async {
      final sedeOk = await fila(tx, '''
        SELECT 1 FROM jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)
        WHERE a.sede IS NULL OR a.sede = CAST(@s:text AS uuid)''', {...a, 's': d['sede_id']});
      if (sedeOk == null) throw ErrorAcceso(403, 'No coordinas esa sede.');
      final paciente = await fila(tx, '''
        INSERT INTO personas.pacientes (codigo_historia, cedula, cedula_huella, nombres, apellidos, fecha_nacimiento,
                                        sexo, direccion, sede_principal_id, estado, creado_por)
        VALUES ((SELECT 'HC-' || lpad((coalesce(max(substring(codigo_historia FROM 4)::int), 0) + 1)::text, 5, '0')
                 FROM personas.pacientes),
                comun.cifrar(@cedula:text, @llave:text), comun.huella(@cedula:text, @llave:text),
                @nombres:text, @apellidos:text, CAST(@nac:text AS date), @sexo:text, @dir:text,
                CAST(@sede:text AS uuid), 'PROSPECTO', CAST(@u:text AS uuid))
        RETURNING id::text, codigo_historia''', {
        'cedula': (d['cedula'] as String?)?.trim().isEmpty ?? true ? null : (d['cedula'] as String).trim(),
        'llave': _llave, 'nombres': d['nombres'], 'apellidos': d['apellidos'], 'nac': d['fecha_nacimiento'],
        'sexo': d['sexo'], 'dir': d['direccion'], 'sede': d['sede_id'], 'u': s.usuarioId,
      });
      final representante = await fila(tx, '''
        WITH existente AS (SELECT id FROM personas.representantes WHERE cedula = @cedula:text),
        nuevo AS (
          INSERT INTO personas.representantes (cedula, nombres, apellidos, telefono, email, direccion, creado_por)
          SELECT @cedula:text, @nombres:text, @apellidos:text, @tel:text, @email:text, @dir:text, CAST(@u:text AS uuid)
          WHERE NOT EXISTS (SELECT 1 FROM existente)
          RETURNING id)
        SELECT id::text FROM existente UNION ALL SELECT id::text FROM nuevo''', {
        'cedula': rep['cedula'].toString().trim(), 'nombres': rep['nombres'], 'apellidos': rep['apellidos'],
        'tel': rep['telefono'], 'email': rep['email'], 'dir': d['direccion'], 'u': s.usuarioId,
      });
      await consultar(tx, '''
        INSERT INTO personas.paciente_representantes (paciente_id, representante_id, parentesco, es_principal)
        VALUES (CAST(@p:text AS uuid), CAST(@r:text AS uuid), @par:text, true)''',
          {'p': paciente!['id'], 'r': representante!['id'], 'par': rep['parentesco']});
      return paciente;
    });
  }

  /// Agenda a un paciente con un terapeuta a una hora. Si el terapeuta ya
  /// tiene una sesión grupal del mismo programa a esa hora, lo suma a ella.
  /// Todas las reglas (jornada, feriados, cupo, choques, saldo) las valida la base.
  Future<Map<String, Object?>> agendar(Sesion s, Map<String, dynamic> d) {
    final a = _alcance(s);
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
      ...a,
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

  Future<void> cancelarSesion(Sesion s, String sesionId, String motivo) {
    final a = _alcance(s);
    return _db.conSesion(s, (tx) async {
      final r = await consultar(tx, '''
        UPDATE agenda.sesiones s SET estado = 'CANCELADA', motivo_cancelacion = @m:text, actualizado_por = CAST(@u:text AS uuid)
        FROM catalogo.programas pg
        WHERE s.id = CAST(@id:text AS uuid) AND s.estado = 'PROGRAMADA' AND pg.id = s.programa_id
          AND ${_enAlcance('s.sede_id', 'pg.area_id')}''', {...a, 'm': motivo, 'u': s.usuarioId, 'id': sesionId});
      if (r.affectedRows == 0) throw ErrorDatos(404, 'La sesión no existe, ya no está programada o no es de tu coordinación.');
      await consultar(tx, '''
        UPDATE agenda.participantes SET asistencia = 'CANCELADA'
        WHERE sesion_id = CAST(@id:text AS uuid) AND asistencia = 'PENDIENTE' ''', {'id': sesionId});
    });
  }

  Future<List<Map<String, dynamic>>> solicitudes(Sesion s, {String estado = 'PENDIENTE', String? area}) {
    final a = _alcance(s, area: area);
    return _db.conSesion(s, (tx) => filas(tx, '''
      SELECT sc.id::text, sc.tipo, sc.origen, sc.motivo, sc.estado,
             to_char(sc.propuesta_inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS propuesta_inicio,
             to_char(sc.creado_en AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD HH24:MI') AS creado_en,
             pa.nombres || ' ' || pa.apellidos AS paciente, pr.nombres || ' ' || pr.apellidos AS terapeuta,
             to_char(s.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS sesion_inicio,
             pg.nombre AS programa, x.paciente_id::text AS paciente_id
      FROM agenda.solicitudes_cambio sc
      JOIN agenda.participantes x ON x.id = sc.participante_id
      JOIN agenda.sesiones s ON s.id = x.sesion_id
      JOIN personas.pacientes pa ON pa.id = x.paciente_id
      JOIN personas.profesionales pr ON pr.id = s.profesional_id
      LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
      WHERE sc.estado = @estado:text AND ${_enAlcance('s.sede_id', 'pg.area_id')}
      ORDER BY sc.creado_en''', {...a, 'estado': estado}));
  }

  /// Aprueba o rechaza. Al aprobar, el paciente sale de esa sesión
  /// (cancelada o por reprogramar) y el coordinador agenda la nueva fecha.
  Future<void> resolverSolicitud(Sesion s, String solicitudId, String estado) {
    if (estado != 'APROBADA' && estado != 'RECHAZADA') throw ErrorDatos(422, 'El estado debe ser APROBADA o RECHAZADA.');
    final a = _alcance(s);
    return _db.conSesion(s, (tx) async {
      final sol = await fila(tx, '''
        UPDATE agenda.solicitudes_cambio sc
           SET estado = @e:text, resuelto_por = CAST(@u:text AS uuid), resuelto_en = now()
        FROM agenda.participantes x, agenda.sesiones s, catalogo.programas pg
        WHERE sc.id = CAST(@id:text AS uuid) AND sc.estado = 'PENDIENTE'
          AND x.id = sc.participante_id AND s.id = x.sesion_id AND pg.id = s.programa_id
          AND ${_enAlcance('s.sede_id', 'pg.area_id')}
        RETURNING sc.tipo, sc.participante_id::text''', {...a, 'e': estado, 'u': s.usuarioId, 'id': solicitudId});
      if (sol == null) throw ErrorDatos(404, 'La solicitud no existe, ya fue resuelta o no es de tu coordinación.');
      if (estado == 'APROBADA') {
        await consultar(tx, '''
          UPDATE agenda.participantes SET asistencia = @a:text WHERE id = CAST(@x:text AS uuid) AND asistencia = 'PENDIENTE' ''',
            {'a': sol['tipo'] == 'CANCELAR' ? 'CANCELADA' : 'REPROGRAMADA', 'x': sol['participante_id']});
      }
    });
  }

  /// Clasifica la demanda del paciente (la base exige nivel de coordinación o superior).
  Future<void> clasificarDemanda(Sesion s, {required String pacienteId, required String nivelId, required String motivo}) {
    _alcance(s);
    return _db.conSesion(s, (tx) => consultar(tx, '''
      INSERT INTO personas.clasificaciones_demanda (paciente_id, nivel_id, motivo, clasificado_por)
      VALUES (CAST(@p:text AS uuid), CAST(@n:text AS uuid), @m:text, CAST(@u:text AS uuid))''',
        {'p': pacienteId, 'n': nivelId, 'm': motivo, 'u': s.usuarioId}));
  }
}
