import 'dart:convert';

/// Nombres visibles de cada módulo (esquema de la base).
const nombresModulos = {
  'organizacion': 'Organización',
  'catalogo': 'Catálogo',
  'seguridad': 'Seguridad',
  'personas': 'Personas',
  'matriculas': 'Matrículas',
  'agenda': 'Agenda',
  'clinico': 'Clínico',
  'desempeno': 'Desempeño',
  'notificaciones': 'Notificaciones',
  'reportes': 'Indicadores',
  'comun': 'Parámetros',
};

/// Orden en que se muestran los módulos en el menú.
const ordenModulos = [
  'personas', 'agenda', 'matriculas', 'clinico', 'desempeno', 'catalogo',
  'organizacion', 'seguridad', 'notificaciones', 'reportes', 'comun',
];

class Referencia {
  const Referencia({required this.esquema, required this.tabla, required this.columna});

  factory Referencia.fromJson(Map<String, dynamic> j) =>
      Referencia(esquema: j['esquema'] as String, tabla: j['tabla'] as String, columna: j['columna'] as String);

  final String esquema;
  final String tabla;
  final String columna;
}

class Columna {
  const Columna({
    required this.nombre,
    required this.tipo,
    required this.tipoSql,
    required this.requerido,
    required this.esClave,
    required this.editable,
    this.comentario,
    this.referencia,
    this.opciones,
  });

  factory Columna.fromJson(Map<String, dynamic> j) => Columna(
        nombre: j['nombre'] as String,
        tipo: j['tipo'] as String,
        tipoSql: j['tipoSql'] as String,
        requerido: j['requerido'] as bool,
        esClave: j['esClave'] as bool,
        editable: j['editable'] as bool,
        comentario: j['comentario'] as String?,
        referencia: j['referencia'] == null ? null : Referencia.fromJson(j['referencia'] as Map<String, dynamic>),
        opciones: (j['opciones'] as List?)?.cast<String>(),
      );

  final String nombre;

  /// uuid, texto, entero, decimal, booleano, fecha, fecha_hora, hora, json,
  /// opcion, referencia, cifrado, secreto, binario u otro.
  final String tipo;
  final String tipoSql;
  final bool requerido;
  final bool esClave;
  final bool editable;
  final String? comentario;
  final Referencia? referencia;
  final List<String>? opciones;

  /// "profesional_id" → "Profesional", "fecha_hora_inicio" → "Fecha hora inicio".
  String get titulo {
    var t = nombre;
    if (referencia != null && t.endsWith('_id')) t = t.substring(0, t.length - 3);
    t = t.replaceAll('_', ' ');
    return t.isEmpty ? nombre : t[0].toUpperCase() + t.substring(1);
  }

  bool get textoLargo =>
      tipo == 'json' ||
      const ['descripcion', 'observaciones', 'motivo', 'contenido', 'cuerpo', 'comentario', 'conclusion', 'formula', 'resumen']
          .any(nombre.contains);
}

class Tabla {
  const Tabla({
    required this.esquema,
    required this.tabla,
    required this.descripcion,
    required this.soloLectura,
    required this.archivable,
    required this.columnas,
  });

  factory Tabla.fromJson(Map<String, dynamic> j) => Tabla(
        esquema: j['esquema'] as String,
        tabla: j['tabla'] as String,
        descripcion: j['descripcion'] as String?,
        soloLectura: j['soloLectura'] as bool,
        archivable: j['archivable'] as bool,
        columnas: [for (final c in j['columnas'] as List) Columna.fromJson(c as Map<String, dynamic>)],
      );

  final String esquema;
  final String tabla;
  final String? descripcion;
  final bool soloLectura;
  final bool archivable;
  final List<Columna> columnas;

  String get id => '$esquema.$tabla';
  String get modulo => nombresModulos[esquema] ?? esquema;
  bool get esVista => tabla.startsWith('v_');

  String get titulo {
    final t = (esVista ? tabla.substring(2) : tabla).replaceAll('_', ' ');
    return t[0].toUpperCase() + t.substring(1);
  }

  List<Columna> get clave => columnas.where((c) => c.esClave).toList();

  /// Clave primaria del registro, como JSON en base64url para la URL.
  String claveDe(Map<String, dynamic> fila) {
    final mapa = {for (final c in clave) c.nombre: fila[c.nombre]};
    return base64Url.encode(utf8.encode(jsonEncode(mapa))).replaceAll('=', '');
  }

  /// Texto que mejor identifica a un registro (para tarjetas y títulos).
  String tituloDe(Map<String, dynamic> fila) {
    String? v(String c) => fila[c]?.toString();
    if (v('nombres') != null && v('apellidos') != null) return '${v('nombres')} ${v('apellidos')}';
    for (final c in const ['nombre', 'codigo', 'titulo', 'email', 'etiqueta', 'descripcion', 'clave']) {
      if (v(c) != null) return v(c)!;
    }
    for (final c in columnas.where((c) => c.referencia != null)) {
      final etiqueta = fila['${c.nombre}__etiqueta'];
      if (etiqueta != null) return etiqueta.toString();
    }
    return clave.map((c) => fila[c.nombre]).join(' · ');
  }
}

class PaginaFilas {
  const PaginaFilas({required this.total, required this.pagina, required this.tamano, required this.filas});

  factory PaginaFilas.fromJson(Map<String, dynamic> j) => PaginaFilas(
        total: j['total'] as int,
        pagina: j['pagina'] as int,
        tamano: j['tamano'] as int,
        filas: (j['filas'] as List).cast<Map<String, dynamic>>(),
      );

  final int total;
  final int pagina;
  final int tamano;
  final List<Map<String, dynamic>> filas;

  int get paginas => total == 0 ? 1 : (total / tamano).ceil();
}

class Opcion {
  const Opcion(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;
}
