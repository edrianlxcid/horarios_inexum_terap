/// Descripción de una tabla leída del catálogo de PostgreSQL.
class TablaInfo {
  TablaInfo({
    required this.esquema,
    required this.tabla,
    required this.descripcion,
    required this.esVista,
    required this.columnas,
  });

  final String esquema;
  final String tabla;
  final String? descripcion;
  final bool esVista;
  final List<ColumnaInfo> columnas;

  /// Tablas que se calculan solas o que solo admiten agregar filas.
  static const _soloLectura = {
    'seguridad.bitacora',
    'reportes.valores_indicador',
    'desempeno.bonos_calculados',
  };

  String get nombreCompleto => '$esquema.$tabla';
  String get sqlNombre => '"$esquema"."$tabla"';
  bool get soloLectura => esVista || _soloLectura.contains(nombreCompleto) || clave.isEmpty;
  List<ColumnaInfo> get clave => columnas.where((c) => c.esClave).toList();
  bool tiene(String columna) => columnas.any((c) => c.nombre == columna);
  ColumnaInfo? columna(String nombre) {
    for (final c in columnas) {
      if (c.nombre == nombre) return c;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'esquema': esquema,
        'tabla': tabla,
        'descripcion': descripcion,
        'soloLectura': soloLectura,
        'archivable': tiene('archivado_en'),
        'columnas': [for (final c in columnas) c.toJson()],
      };
}

/// Columna con lo necesario para mostrarla y editarla desde la interfaz.
class ColumnaInfo {
  ColumnaInfo({
    required this.nombre,
    required this.tipoSql,
    required this.requerido,
    required this.tieneDefecto,
    required this.generada,
    required this.esClave,
    required this.comentario,
    required this.referencia,
    required this.opciones,
    required this.cifrada,
  });

  final String nombre;
  final String tipoSql;
  final bool requerido;
  final bool tieneDefecto;
  final bool generada;
  final bool esClave;
  final String? comentario;
  final Referencia? referencia;
  final List<String>? opciones;

  /// Dato sensible cifrado con la llave de la API (se descifra para mostrarlo).
  final bool cifrada;

  static const _sistema = {'creado_en', 'actualizado_en', 'cedula_huella', 'empresa_id'};
  static const _secretas = {'password_hash', 'refresh_token_hash', 'mfa_secreto', 'cedula_huella'};

  bool get esSecreta => _secretas.contains(nombre);

  /// Tipo simplificado para la interfaz.
  String get tipo {
    if (esSecreta) return 'secreto';
    if (cifrada) return 'cifrado';
    if (opciones != null) return 'opcion';
    if (referencia != null) return 'referencia';
    final t = tipoSql;
    if (t == 'uuid') return 'uuid';
    if (t == 'boolean') return 'booleano';
    if (t == 'date') return 'fecha';
    if (t.startsWith('timestamp')) return 'fecha_hora';
    if (t.startsWith('time')) return 'hora';
    if (t == 'smallint' || t == 'integer' || t == 'bigint') return 'entero';
    if (t.startsWith('numeric')) return 'decimal';
    if (t == 'jsonb' || t == 'json') return 'json';
    if (t == 'bytea') return 'binario';
    if (t == 'text' || t.startsWith('character')) return 'texto';
    return 'otro';
  }

  bool get editable =>
      !generada && !_sistema.contains(nombre) && tipo != 'binario' && tipo != 'otro' && nombre != 'mfa_secreto';

  Map<String, Object?> toJson() => {
        'nombre': nombre,
        'tipo': tipo,
        'tipoSql': tipoSql,
        'requerido': requerido && !tieneDefecto && !generada,
        'esClave': esClave,
        'editable': editable,
        'comentario': comentario,
        'referencia': referencia?.toJson(),
        'opciones': opciones,
      };
}

class Referencia {
  Referencia(this.esquema, this.tabla, this.columna);

  final String esquema;
  final String tabla;
  final String columna;

  String get nombreCompleto => '$esquema.$tabla';

  Map<String, Object?> toJson() => {'esquema': esquema, 'tabla': tabla, 'columna': columna};
}

/// Error con un mensaje pensado para mostrarse tal cual al usuario.
class ErrorDatos implements Exception {
  ErrorDatos(this.estado, this.mensaje);

  final int estado;
  final String mensaje;

  @override
  String toString() => mensaje;
}
