import 'package:backend/modules/herramienta_datos/modelos.dart';
import 'package:postgres/postgres.dart';

/// Acceso genérico a las tablas de la base, a partir del catálogo de PostgreSQL.
///
/// Los nombres de tablas y columnas salen siempre del catálogo (nunca del
/// usuario) y los valores siempre van como parámetros: no hay inyección SQL.
class DatosRepositorio {
  DatosRepositorio(this._db, this._llave);

  final Session _db;
  final String _llave;
  // El catálogo es igual para todas las empresas: se guarda una sola vez.
  static List<TablaInfo>? _cache;

  static const esquemas = [
    'organizacion', 'catalogo', 'seguridad', 'personas', 'matriculas',
    'agenda', 'clinico', 'desempeno', 'notificaciones', 'reportes', 'comun',
  ];

  /// Columnas cifradas con la llave de la API y, si existe, su columna de huella.
  static const _cifradas = {
    'personas.pacientes.cedula': 'cedula_huella',
    'clinico.notas_sesion.contenido': null,
    'clinico.notas_anexos.contenido': null,
    'clinico.valoraciones.resultados': null,
  };

  /// Cómo mostrar un registro cuando otra tabla lo referencia (alias t).
  static const _etiquetasEspeciales = {
    'agenda.sesiones':
        "to_char(t.inicio AT TIME ZONE 'America/Guayaquil', 'DD/MM/YYYY HH24:MI') || ' · ' || t.tipo",
    'agenda.participantes':
        "(SELECT p.nombres || ' ' || p.apellidos FROM personas.pacientes p WHERE p.id = t.paciente_id)"
            " || ' · sesión ' || coalesce(t.numero_sesion::text, '-')",
    'matriculas.matriculas':
        "(SELECT p.nombres || ' ' || p.apellidos FROM personas.pacientes p WHERE p.id = t.paciente_id)"
            " || ' · ' || (SELECT g.nombre FROM catalogo.programas g WHERE g.id = t.programa_id)",
    'agenda.planes_agenda':
        "'Plan desde ' || to_char(t.fecha_inicio, 'DD/MM/YYYY')",
    'clinico.notas_sesion': "'Nota del ' || to_char(t.creado_en, 'DD/MM/YYYY')",
    'organizacion.rucs': 't.numero_ruc',
  };

  // ---------------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------------
  Future<List<TablaInfo>> tablas({bool refrescar = false}) async {
    if (_cache != null && !refrescar) return _cache!;
    final filas = await _db.execute('''
      SELECT n.nspname, c.relname, c.relkind::text, obj_description(c.oid, 'pg_class'),
             a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
             d.adbin IS NOT NULL OR a.attidentity <> '', a.attgenerated <> '' OR a.attidentity = 'a',
             coalesce(a.attnum = ANY (pk.conkey), false),
             col_description(c.oid, a.attnum),
             fk.ref_esquema, fk.ref_tabla, fk.ref_columna, ck.definicion
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
      LEFT JOIN pg_constraint pk ON pk.conrelid = c.oid AND pk.contype = 'p'
      LEFT JOIN LATERAL (
        SELECT rn.nspname AS ref_esquema, rc.relname AS ref_tabla, ra.attname AS ref_columna
        FROM pg_constraint f
        JOIN pg_class rc ON rc.oid = f.confrelid
        JOIN pg_namespace rn ON rn.oid = rc.relnamespace
        JOIN pg_attribute ra ON ra.attrelid = f.confrelid AND ra.attnum = f.confkey[1]
        WHERE f.conrelid = c.oid AND f.contype = 'f' AND cardinality(f.conkey) = 1 AND f.conkey[1] = a.attnum
        LIMIT 1
      ) fk ON true
      LEFT JOIN LATERAL (
        SELECT pg_get_constraintdef(k.oid) AS definicion
        FROM pg_constraint k
        WHERE k.conrelid = c.oid AND k.contype = 'c' AND k.conkey = ARRAY[a.attnum]::int2[]
          AND pg_get_constraintdef(k.oid) LIKE '%ANY (ARRAY[%'
        LIMIT 1
      ) ck ON true
      WHERE n.nspname IN ('organizacion', 'catalogo', 'seguridad', 'personas', 'matriculas',
                          'agenda', 'clinico', 'desempeno', 'notificaciones', 'reportes', 'comun')
        AND c.relkind IN ('r', 'p', 'v') AND NOT c.relispartition
      ORDER BY n.nspname, c.relname, a.attnum''');

    final porTabla = <String, TablaInfo>{};
    final valorCheck = RegExp(r"'([^']*)'::");
    for (final f in filas) {
      final esquema = f[0]! as String;
      final tabla = f[1]! as String;
      final info = porTabla.putIfAbsent(
        '$esquema.$tabla',
        () => TablaInfo(
          esquema: esquema,
          tabla: tabla,
          descripcion: f[3] as String?,
          esVista: f[2] == 'v',
          columnas: [],
        ),
      );
      final nombre = f[4]! as String;
      final definicionCheck = f[14] as String?;
      info.columnas.add(
        ColumnaInfo(
          nombre: nombre,
          tipoSql: f[5]! as String,
          requerido: f[6]! as bool,
          tieneDefecto: f[7]! as bool,
          generada: f[8]! as bool,
          esClave: f[9]! as bool,
          comentario: f[10] as String?,
          referencia: f[11] == null ? null : Referencia(f[11]! as String, f[12]! as String, f[13]! as String),
          opciones: definicionCheck == null
              ? null
              : valorCheck.allMatches(definicionCheck).map((m) => m.group(1)!).toList(),
          cifrada: _cifradas.containsKey('$esquema.$tabla.$nombre'),
        ),
      );
    }
    return _cache = porTabla.values.toList();
  }

  Future<TablaInfo> tabla(String esquema, String tabla) async {
    for (final t in await tablas()) {
      if (t.esquema == esquema && t.tabla == tabla) return t;
    }
    throw ErrorDatos(404, 'No existe la tabla $esquema.$tabla');
  }

  // ---------------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------------
  Future<Map<String, Object?>> filas(
    TablaInfo info, {
    String busqueda = '',
    int pagina = 1,
    int tamano = 25,
  }) async {
    final parametros = <String, Object?>{'llave': _llave};
    final filtro = _filtroBusqueda(info, busqueda, parametros);
    final columnas = <String>[];
    for (final c in info.columnas) {
      columnas.add('${_lectura(c)} AS "${c.nombre}"');
      final ref = c.referencia;
      if (ref != null) {
        final destino = await tabla(ref.esquema, ref.tabla);
        columnas.add(
          '(SELECT ${_etiqueta(destino)} FROM ${destino.sqlNombre} t '
          'WHERE t."${ref.columna}" = x."${c.nombre}") AS "${c.nombre}__etiqueta"',
        );
      }
    }

    final total = await _ejecutar('SELECT count(*) FROM ${info.sqlNombre} x WHERE $filtro', parametros);
    final resultado = await _ejecutar(
      'SELECT ${columnas.join(', ')} FROM ${info.sqlNombre} x WHERE $filtro '
      'ORDER BY ${_orden(info)} LIMIT @tamano:int4 OFFSET @desde:int4',
      {...parametros, 'tamano': tamano, 'desde': (pagina - 1) * tamano},
    );
    return {
      'total': total.first.first,
      'pagina': pagina,
      'tamano': tamano,
      'filas': [for (final r in resultado) r.toColumnMap()],
    };
  }

  /// Opciones para elegir un registro referenciado (listas desplegables).
  Future<List<Map<String, Object?>>> opciones(TablaInfo info, String busqueda) async {
    final clave = info.clave.isEmpty ? info.columnas.first : info.clave.first;
    final etiqueta = _etiqueta(info);
    final resultado = await _ejecutar(
      'SELECT t."${clave.nombre}"::text AS valor, $etiqueta AS etiqueta FROM ${info.sqlNombre} t '
      "WHERE @q:text = '' OR ($etiqueta) ILIKE '%' || @q:text || '%' "
      'ORDER BY 2 LIMIT 30',
      {'q': busqueda},
    );
    return [for (final r in resultado) r.toColumnMap()];
  }

  // ---------------------------------------------------------------------------
  // Escritura
  // ---------------------------------------------------------------------------
  Future<Map<String, Object?>> crear(TablaInfo info, Map<String, Object?> valores) async {
    final parametros = <String, Object?>{'llave': _llave};
    final columnas = <String>[];
    final expresiones = <String>[];
    var i = 0;
    for (final e in valores.entries) {
      final c = info.columna(e.key)!;
      final p = 'v${i++}';
      parametros[p] = e.value;
      columnas.add('"${c.nombre}"');
      expresiones.add(_escritura(c, p));
      final huella = _cifradas['${info.nombreCompleto}.${c.nombre}'];
      if (huella != null) {
        columnas.add('"$huella"');
        expresiones.add(_huella(p));
      }
    }
    final retorno = info.clave.map((c) => '"${c.nombre}"::text AS "${c.nombre}"').join(', ');
    final sql = columnas.isEmpty
        ? 'INSERT INTO ${info.sqlNombre} DEFAULT VALUES RETURNING $retorno'
        : 'INSERT INTO ${info.sqlNombre} (${columnas.join(', ')}) VALUES (${expresiones.join(', ')}) RETURNING $retorno';
    final r = await _ejecutar(sql, parametros);
    return r.first.toColumnMap();
  }

  Future<void> actualizar(TablaInfo info, Map<String, Object?> clave, Map<String, Object?> valores) async {
    if (valores.isEmpty) return;
    final parametros = <String, Object?>{'llave': _llave};
    final asignaciones = <String>[];
    var i = 0;
    for (final e in valores.entries) {
      final c = info.columna(e.key)!;
      final p = 'v${i++}';
      parametros[p] = e.value;
      asignaciones.add('"${c.nombre}" = ${_escritura(c, p)}');
      final huella = _cifradas['${info.nombreCompleto}.${c.nombre}'];
      if (huella != null) asignaciones.add('"$huella" = ${_huella(p)}');
    }
    final condicion = _porClave(info, clave, parametros);
    final r = await _ejecutar('UPDATE ${info.sqlNombre} x SET ${asignaciones.join(', ')} WHERE $condicion', parametros);
    if (r.affectedRows == 0) throw ErrorDatos(404, 'El registro ya no existe');
  }

  /// Archiva el registro si la tabla lo permite; si no, intenta borrarlo.
  Future<String> eliminar(TablaInfo info, Map<String, Object?> clave) async {
    final parametros = <String, Object?>{};
    final condicion = _porClave(info, clave, parametros);
    final archivar = info.tiene('archivado_en');
    final sql = archivar
        ? 'UPDATE ${info.sqlNombre} x SET archivado_en = now() WHERE $condicion AND archivado_en IS NULL'
        : 'DELETE FROM ${info.sqlNombre} x WHERE $condicion';
    final r = await _ejecutar(sql, parametros);
    if (r.affectedRows == 0) throw ErrorDatos(404, 'El registro no existe o ya estaba archivado');
    return archivar ? 'archivado' : 'eliminado';
  }

  // ---------------------------------------------------------------------------
  // Construcción de SQL
  // ---------------------------------------------------------------------------

  /// Ejecuta pasando solo los parámetros que aparecen en el SQL (el driver
  /// rechaza parámetros sobrantes).
  Future<Result> _ejecutar(String sql, Map<String, Object?> parametros) {
    final usados = {
      for (final e in parametros.entries)
        if (RegExp('@${e.key}\\b').hasMatch(sql)) e.key: e.value,
    };
    return _db.execute(Sql.named(sql), parameters: usados);
  }

  String _lectura(ColumnaInfo c) {
    final col = 'x."${c.nombre}"';
    return switch (c.tipo) {
      'secreto' => "CASE WHEN $col IS NULL THEN NULL ELSE '••••••' END",
      'cifrado' => 'comun.descifrar($col, @llave:text)',
      'binario' => "CASE WHEN $col IS NULL THEN NULL ELSE '[dato binario]' END",
      'fecha_hora' => "to_char($col AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD HH24:MI')",
      'hora' => "to_char($col, 'HH24:MI')",
      _ => '$col::text',
    };
  }

  String _escritura(ColumnaInfo c, String p) {
    final valor = 'CAST(@$p:text AS text)';
    return switch (c.tipo) {
      'secreto' => "crypt($valor, gen_salt('bf', 10))",
      'cifrado' => 'comun.cifrar($valor, @llave:text)',
      'fecha_hora' => "(CAST($valor AS timestamp) AT TIME ZONE 'America/Guayaquil')",
      _ => 'CAST($valor AS ${c.tipoSql})',
    };
  }

  String _huella(String p) => 'comun.huella(CAST(@$p:text AS text), @llave:text)';

  String _porClave(TablaInfo info, Map<String, Object?> clave, Map<String, Object?> parametros) {
    if (info.clave.isEmpty) throw ErrorDatos(400, 'La tabla no tiene clave primaria');
    final partes = <String>[];
    for (final (i, c) in info.clave.indexed) {
      if (!clave.containsKey(c.nombre)) throw ErrorDatos(400, 'Falta la clave ${c.nombre}');
      parametros['k$i'] = clave[c.nombre]?.toString();
      partes.add('x."${c.nombre}"::text = CAST(@k$i:text AS text)');
    }
    return partes.join(' AND ');
  }

  String _filtroBusqueda(TablaInfo info, String busqueda, Map<String, Object?> parametros) {
    final q = busqueda.trim();
    if (q.isEmpty) return 'true';
    parametros['q'] = '%$q%';
    final partes = <String>[];
    for (final c in info.columnas) {
      if (const {'texto', 'opcion', 'uuid', 'fecha', 'entero'}.contains(c.tipo)) {
        partes.add('x."${c.nombre}"::text ILIKE @q:text');
      }
    }
    for (final entrada in _cifradas.entries) {
      if (entrada.value != null && entrada.key.startsWith('${info.nombreCompleto}.')) {
        parametros['exacto'] = q;
        partes.add('x."${entrada.value}" = comun.huella(@exacto:text, @llave:text)');
      }
    }
    return partes.isEmpty ? 'true' : '(${partes.join(' OR ')})';
  }

  String _orden(TablaInfo info) {
    for (final c in const ['inicio', 'fecha', 'ocurrido_en', 'creado_en']) {
      if (info.tiene(c)) return 'x."$c" DESC';
    }
    if (info.tiene('orden')) return 'x."orden"';
    if (info.clave.isNotEmpty) return info.clave.map((c) => 'x."${c.nombre}"').join(', ');
    return '1';
  }

  String _etiqueta(TablaInfo info) {
    final especial = _etiquetasEspeciales[info.nombreCompleto];
    if (especial != null) return especial;
    if (info.tiene('nombres') && info.tiene('apellidos')) return "t.nombres || ' ' || t.apellidos";
    for (final c in const ['nombre', 'codigo', 'etiqueta', 'email', 'titulo', 'descripcion']) {
      if (info.tiene(c)) return 't."$c"::text';
    }
    final clave = info.clave.isEmpty ? info.columnas.first : info.clave.first;
    return 't."${clave.nombre}"::text';
  }
}
