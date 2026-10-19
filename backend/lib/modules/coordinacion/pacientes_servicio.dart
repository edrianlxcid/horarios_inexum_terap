import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';
import 'package:postgres/postgres.dart';

/// Pacientes (estudiantes) para coordinación: listado con contrato y avance,
/// ficha completa, registro y clasificación de la demanda.
class PacientesCoordinacion {
  PacientesCoordinacion(this._db, this._llave);

  final BaseDatos _db;
  final String _llave;

  static const tamanoPagina = 25;
  static final _cedula = RegExp(r'^[0-9]{10}$');
  static final _correo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Listado paginado. La búsqueda acepta nombre, historia clínica, número de
  /// contrato, nombre o cédula del representante, o la cédula exacta del paciente.
  Future<Map<String, Object?>> lista(
    Sesion s, {
    String q = '',
    String? area,
    String? sede,
    String? estado,
    String? profesional,
    String? programa,
    int pagina = 1,
  }) {
    final a = Alcance.de(s, area: area);
    final p = {
      ...a.parametros,
      'q': q.trim(), 'qq': '%${q.trim()}%', 'llave': _llave, 'desde': (pagina - 1) * tamanoPagina,
      'sede': sede ?? '', 'estado': estado ?? '', 'prof': profesional ?? '', 'prog': programa ?? '',
    };
    const filtro = '''
      FROM personas.pacientes pa
      JOIN organizacion.sedes se ON se.id = pa.sede_principal_id
      WHERE pa.archivado_en IS NULL
        AND (@sede:text = '' OR pa.sede_principal_id = CAST(nullif(@sede:text, '') AS uuid))
        AND (@estado:text = '' OR pa.estado = @estado:text)
        AND (@prog:text = '' OR EXISTS (SELECT 1 FROM matriculas.matriculas m WHERE m.paciente_id = pa.id
                                        AND m.programa_id = CAST(nullif(@prog:text, '') AS uuid)))
        AND (@prof:text = '' OR EXISTS (SELECT 1 FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
                                        WHERE x.paciente_id = pa.id AND s.profesional_id = CAST(nullif(@prof:text, '') AS uuid)
                                          AND s.estado <> 'CANCELADA' AND s.inicio >= now() - interval '60 days'))
        AND (@q:text = '' OR lower(pa.nombres || ' ' || pa.apellidos) LIKE lower(@qq:text) OR pa.codigo_historia ILIKE @qq:text
             OR pa.cedula_huella = comun.huella(@q:text, @llave:text)
             OR EXISTS (SELECT 1 FROM matriculas.matriculas m JOIN matriculas.contratos c ON c.id = m.contrato_id
                        WHERE m.paciente_id = pa.id AND c.codigo ILIKE @qq:text)
             OR EXISTS (SELECT 1 FROM personas.paciente_representantes x JOIN personas.representantes r ON r.id = x.representante_id
                        WHERE x.paciente_id = pa.id AND (r.cedula = @q:text OR lower(r.nombres || ' ' || r.apellidos) LIKE lower(@qq:text))))''';
    return _db.conSesion(s, (tx) async {
      final total = await fila(tx, 'SELECT count(*)::int AS n $filtro AND ${Alcance.paciente('pa')}', p);
      final lista = await filas(tx, '''
        SELECT pa.id::text, pa.codigo_historia, pa.nombres, pa.apellidos, pa.estado, se.nombre AS sede,
               (extract(year FROM age(pa.fecha_nacimiento)) * 12 + extract(month FROM age(pa.fecha_nacimiento)))::int AS edad_meses,
               (SELECT nd.nombre FROM personas.clasificaciones_demanda cd JOIN personas.niveles_demanda nd ON nd.id = cd.nivel_id
                WHERE cd.paciente_id = pa.id AND cd.vigente) AS demanda,
               (SELECT json_build_object('nombre', r.nombres || ' ' || r.apellidos, 'telefono', r.telefono)
                FROM personas.paciente_representantes x JOIN personas.representantes r ON r.id = x.representante_id
                WHERE x.paciente_id = pa.id ORDER BY x.es_principal DESC LIMIT 1) AS representante,
               coalesce((SELECT json_agg(json_build_object('codigo', c.codigo, 'estado', c.estado)
                                         ORDER BY c.estado <> 'VIGENTE', c.vigente_hasta DESC)
                         FROM matriculas.contratos c
                         WHERE c.id IN (SELECT m.contrato_id FROM matriculas.matriculas m WHERE m.paciente_id = pa.id)), '[]'::json) AS contratos,
               coalesce((SELECT json_agg(json_build_object('programa', pg.nombre, 'estado', m.estado,
                                         'contratadas', m.sesiones_contratadas,
                                         'realizadas', (SELECT count(*) FROM agenda.participantes x
                                                        WHERE x.matricula_id = m.id AND x.asistencia IN ('ASISTIO', 'FALTA')))
                                         ORDER BY pg.nombre)
                         FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
                         WHERE m.paciente_id = pa.id AND m.estado IN ('EN_CURSO', 'CONGELADA')), '[]'::json) AS programas,
               -- OFFSET 0 obliga a partir de las sesiones del paciente (índice por
               -- paciente); sin él, el planificador recorre todas las de cada terapeuta.
               (SELECT string_agg(t.nombre, ', ' ORDER BY t.nombre)
                FROM (SELECT DISTINCT s.profesional_id FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
                      WHERE x.paciente_id = pa.id AND s.estado <> 'CANCELADA' AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')
                        AND s.inicio >= now() - interval '60 days' OFFSET 0) u
                CROSS JOIN LATERAL (SELECT pr.nombres || ' ' || pr.apellidos AS nombre
                                    FROM personas.profesionales pr WHERE pr.id = u.profesional_id) t) AS terapeutas,
               (SELECT to_char(min(s.inicio) AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI')
                FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
                WHERE x.paciente_id = pa.id AND s.estado = 'PROGRAMADA' AND x.asistencia = 'PENDIENTE' AND s.inicio >= now()) AS proxima_sesion
        $filtro AND ${Alcance.paciente('pa')}
        ORDER BY pa.apellidos, pa.nombres LIMIT $tamanoPagina OFFSET @desde:int4''', p);
      return {'total': total!['n'], 'pagina': pagina, 'tamano': tamanoPagina, 'filas': lista};
    });
  }

  /// Ficha completa. Descifra la cédula y deja la lectura en la bitácora.
  Future<Map<String, Object?>> ficha(Sesion s, String pacienteId) {
    final a = Alcance.de(s);
    final p = {...a.parametros, 'id': pacienteId, 'llave': _llave};
    return _db.conSesion(s, (tx) async {
      final datos = await fila(tx, '''
        SELECT pa.id::text, pa.codigo_historia, pa.nombres, pa.apellidos, comun.descifrar(pa.cedula, @llave:text) AS cedula,
               to_char(pa.fecha_nacimiento, 'YYYY-MM-DD') AS fecha_nacimiento,
               (extract(year FROM age(pa.fecha_nacimiento)) * 12 + extract(month FROM age(pa.fecha_nacimiento)))::int AS edad_meses,
               pa.sexo, pa.direccion, pa.estado, pa.sede_principal_id::text AS sede_id, se.nombre AS sede, pa.observaciones,
               to_char(pa.creado_en AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD') AS registrado_en,
               nd.nombre AS demanda, cd.motivo AS motivo_demanda
        FROM personas.pacientes pa
        JOIN organizacion.sedes se ON se.id = pa.sede_principal_id
        LEFT JOIN personas.clasificaciones_demanda cd ON cd.paciente_id = pa.id AND cd.vigente
        LEFT JOIN personas.niveles_demanda nd ON nd.id = cd.nivel_id
        WHERE pa.id = CAST(@id:text AS uuid) AND ${Alcance.paciente('pa')}''', p);
      if (datos == null) throw ErrorDatos(404, 'Ese paciente no está en tu coordinación.');
      await consultar(tx, "SELECT seguridad.registrar_lectura('personas.pacientes', @id:text)", p);
      return {
        ...datos,
        'representantes': await filas(tx, '''
          SELECT r.id::text, r.nombres, r.apellidos, r.cedula, r.telefono, r.email, pr.parentesco, pr.es_principal,
                 r.usuario_id IS NOT NULL AS tiene_cuenta
          FROM personas.paciente_representantes pr JOIN personas.representantes r ON r.id = pr.representante_id
          WHERE pr.paciente_id = CAST(@id:text AS uuid) ORDER BY pr.es_principal DESC''', p),
        'contratos': await filas(tx, '''
          SELECT c.id::text, c.codigo, c.tipo, c.estado, c.valor_total::float8 AS valor_total, se.nombre AS sede,
                 to_char(c.fecha_firma, 'YYYY-MM-DD') AS fecha_firma,
                 to_char(c.vigente_desde, 'YYYY-MM-DD') AS vigente_desde, to_char(c.vigente_hasta, 'YYYY-MM-DD') AS vigente_hasta,
                 r.nombres || ' ' || r.apellidos AS firmante
          FROM matriculas.contratos c
          JOIN organizacion.sedes se ON se.id = c.sede_id
          JOIN personas.representantes r ON r.id = c.representante_id
          WHERE c.id IN (SELECT contrato_id FROM matriculas.matriculas WHERE paciente_id = CAST(@id:text AS uuid))
          ORDER BY c.estado <> 'VIGENTE', c.vigente_desde DESC''', p),
        'matriculas': await filas(tx, '''
          SELECT v.matricula_id::text AS id, m.contrato_id::text, c.codigo AS contrato, pg.id::text AS programa_id,
                 pg.nombre AS programa, pg.area_id::text AS area_id, ar.nombre AS area, pg.modalidad, v.estado,
                 v.sesiones_contratadas::int AS contratadas, v.sesiones_consumidas::int AS realizadas,
                 v.sesiones_agendadas::int AS agendadas, v.sesiones_por_agendar::int AS por_agendar, f.nombre AS fase,
                 m.jornada_preferida, to_char(m.fecha_inicio, 'YYYY-MM-DD') AS inicio,
                 to_char(m.fecha_fin_estimada, 'YYYY-MM-DD') AS fin,
                 (SELECT g.codigo FROM agenda.grupo_miembros gm JOIN agenda.grupos g ON g.id = gm.grupo_id
                  WHERE gm.matricula_id = m.id AND coalesce(gm.hasta, 'infinity') >= current_date LIMIT 1) AS grupo,
                 (SELECT string_agg(pr.nombres || ' ' || pr.apellidos, ', ' ORDER BY pr.nombres)
                  FROM personas.profesionales pr
                  WHERE pr.id IN (SELECT s.profesional_id FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
                                  WHERE x.matricula_id = m.id AND s.estado <> 'CANCELADA'
                                    AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA'))) AS terapeutas
          FROM matriculas.v_saldo_sesiones v
          JOIN matriculas.matriculas m ON m.id = v.matricula_id
          JOIN matriculas.contratos c ON c.id = m.contrato_id
          JOIN catalogo.programas pg ON pg.id = v.programa_id
          JOIN catalogo.areas ar ON ar.id = pg.area_id
          LEFT JOIN catalogo.programa_fases f ON f.id = m.fase_actual_id
          WHERE m.paciente_id = CAST(@id:text AS uuid) ORDER BY m.fecha_inicio DESC''', p),
        'asistencia': await fila(tx, '''
          SELECT count(*) FILTER (WHERE x.asistencia = 'ASISTIO')::int AS asistio,
                 count(*) FILTER (WHERE x.asistencia = 'FALTA')::int AS falta,
                 count(*) FILTER (WHERE x.asistencia = 'FALTA_JUSTIFICADA')::int AS justificada
          FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
          WHERE x.paciente_id = CAST(@id:text AS uuid) AND s.inicio < now()''', p),
        'proximas_sesiones': await _sesiones(tx, p, futuras: true),
        'ultimas_sesiones': await _sesiones(tx, p, futuras: false),
      };
    });
  }

  Future<List<Map<String, dynamic>>> _sesiones(Session tx, Map<String, Object?> p, {required bool futuras}) => filas(tx, '''
    SELECT x.id::text AS participante_id, s.id::text AS sesion_id,
           to_char(s.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS inicio,
           s.tipo, pg.nombre AS programa, s.profesional_id::text AS profesional_id,
           pr.nombres || ' ' || pr.apellidos AS terapeuta, x.numero_sesion, x.asistencia
    FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
    JOIN personas.profesionales pr ON pr.id = s.profesional_id
    LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
    WHERE x.paciente_id = CAST(@id:text AS uuid) AND s.inicio ${futuras ? '>=' : '<'} now()
      ${futuras ? "AND s.estado <> 'CANCELADA' AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')" : ''}
    ORDER BY s.inicio ${futuras ? 'ASC' : 'DESC'} LIMIT 8''', p);

  /// Registra un paciente nuevo y su representante principal (o lo vincula si ya existe).
  Future<Map<String, Object?>> crear(Sesion s, Map<String, dynamic> d) {
    final a = Alcance.de(s);
    String? texto(Map<String, dynamic> m, String c) {
      final v = (m[c] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    final rep = (d['representante'] as Map?)?.cast<String, dynamic>();
    if (rep == null) throw ErrorDatos(422, 'Falta el representante.');
    for (final (c, nombre) in const [('nombres', 'los nombres'), ('apellidos', 'los apellidos'),
                                     ('fecha_nacimiento', 'la fecha de nacimiento'), ('sede_id', 'la sede')]) {
      if (texto(d, c) == null) throw ErrorDatos(422, 'Falta completar $nombre del paciente.');
    }
    for (final (c, nombre) in const [('cedula', 'la cédula'), ('nombres', 'los nombres'), ('apellidos', 'los apellidos'),
                                     ('parentesco', 'el parentesco')]) {
      if (texto(rep, c) == null) throw ErrorDatos(422, 'Falta completar $nombre del representante.');
    }
    final cedula = texto(d, 'cedula');
    if (cedula != null && !_cedula.hasMatch(cedula)) throw ErrorDatos(422, 'La cédula del paciente debe tener 10 dígitos.');
    if (!_cedula.hasMatch(texto(rep, 'cedula')!)) throw ErrorDatos(422, 'La cédula del representante debe tener 10 dígitos.');
    final email = texto(rep, 'email');
    if (email != null && !_correo.hasMatch(email)) throw ErrorDatos(422, 'El correo del representante no es válido.');
    final nacimiento = DateTime.tryParse(texto(d, 'fecha_nacimiento')!);
    if (nacimiento == null || nacimiento.isAfter(DateTime.now())) throw ErrorDatos(422, 'La fecha de nacimiento no es válida.');

    return _db.conSesion(s, (tx) async {
      final sedeOk = await fila(tx, 'SELECT 1 WHERE ${Alcance.sede('CAST(@s:text AS uuid)')}', {...a.parametros, 's': d['sede_id']});
      if (sedeOk == null) throw ErrorAcceso(403, 'No coordinas esa sede.');
      if (cedula != null &&
          await fila(tx, 'SELECT 1 FROM personas.pacientes WHERE cedula_huella = comun.huella(@c:text, @llave:text)',
                  {'c': cedula, 'llave': _llave}) != null) {
        throw ErrorDatos(409, 'Ya existe un paciente con esa cédula.');
      }
      final paciente = await fila(tx, '''
        INSERT INTO personas.pacientes (codigo_historia, cedula, cedula_huella, nombres, apellidos, fecha_nacimiento,
                                        sexo, direccion, observaciones, sede_principal_id, estado, creado_por)
        VALUES ((SELECT 'HC-' || lpad((coalesce(max(substring(codigo_historia FROM 4)::int), 0) + 1)::text, 5, '0')
                 FROM personas.pacientes),
                comun.cifrar(@cedula:text, @llave:text), comun.huella(@cedula:text, @llave:text),
                @nombres:text, @apellidos:text, CAST(@nac:text AS date), @sexo:text, @dir:text, @obs:text,
                CAST(@sede:text AS uuid), 'PROSPECTO', CAST(@u:text AS uuid))
        RETURNING id::text, codigo_historia''', {
        'cedula': cedula, 'llave': _llave, 'nombres': texto(d, 'nombres'), 'apellidos': texto(d, 'apellidos'),
        'nac': texto(d, 'fecha_nacimiento'), 'sexo': texto(d, 'sexo'), 'dir': texto(d, 'direccion'),
        'obs': texto(d, 'observaciones'), 'sede': d['sede_id'], 'u': s.usuarioId,
      });
      final representante = await fila(tx, '''
        WITH existente AS (SELECT id FROM personas.representantes WHERE cedula = @cedula:text),
        nuevo AS (
          INSERT INTO personas.representantes (cedula, nombres, apellidos, telefono, email, direccion, creado_por)
          SELECT @cedula:text, @nombres:text, @apellidos:text, @tel:text, @email:text, @dir:text, CAST(@u:text AS uuid)
          WHERE NOT EXISTS (SELECT 1 FROM existente)
          RETURNING id)
        SELECT id::text FROM existente UNION ALL SELECT id::text FROM nuevo''', {
        'cedula': texto(rep, 'cedula'), 'nombres': texto(rep, 'nombres'), 'apellidos': texto(rep, 'apellidos'),
        'tel': texto(rep, 'telefono'), 'email': email, 'dir': texto(d, 'direccion'), 'u': s.usuarioId,
      });
      await consultar(tx, '''
        INSERT INTO personas.paciente_representantes (paciente_id, representante_id, parentesco, es_principal)
        VALUES (CAST(@p:text AS uuid), CAST(@r:text AS uuid), @par:text, true)''',
          {'p': paciente!['id'], 'r': representante!['id'], 'par': texto(rep, 'parentesco')});
      return paciente;
    });
  }

  /// Clasifica la demanda del paciente (la base exige nivel de coordinación o superior).
  Future<void> clasificarDemanda(Sesion s, {required String pacienteId, required String nivelId, required String motivo}) {
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async {
      final visible = await fila(tx, 'SELECT 1 FROM personas.pacientes pa WHERE pa.id = CAST(@id:text AS uuid) AND ${Alcance.paciente('pa')}',
          {...a.parametros, 'id': pacienteId});
      if (visible == null) throw ErrorDatos(404, 'Ese paciente no está en tu coordinación.');
      await consultar(tx, '''
        INSERT INTO personas.clasificaciones_demanda (paciente_id, nivel_id, motivo, clasificado_por)
        VALUES (CAST(@p:text AS uuid), CAST(@n:text AS uuid), @m:text, CAST(@u:text AS uuid))''',
          {'p': pacienteId, 'n': nivelId, 'm': motivo, 'u': s.usuarioId});
    });
  }
}
