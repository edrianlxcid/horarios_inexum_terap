import 'dart:convert';

import 'package:backend/modules/herramienta_datos/datos_repositorio.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Reglas de la herramienta de datos: qué se puede escribir y en qué formato.
/// Las reglas de negocio las sigue validando la base de datos.
class DatosServicio {
  DatosServicio(this._repo);

  final DatosRepositorio _repo;

  Future<List<Map<String, Object?>>> tablas() async =>
      [for (final t in await _repo.tablas()) t.toJson()];

  Future<Map<String, Object?>> filas(String esquema, String tabla, {String q = '', int pagina = 1, int tamano = 25}) async {
    final info = await _repo.tabla(esquema, tabla);
    return _repo.filas(info, busqueda: q, pagina: pagina < 1 ? 1 : pagina, tamano: tamano.clamp(5, 100));
  }

  Future<List<Map<String, Object?>>> opciones(String esquema, String tabla, String q) async =>
      _repo.opciones(await _repo.tabla(esquema, tabla), q);

  Future<Map<String, Object?>> crear(String esquema, String tabla, Map<String, Object?> datos) async {
    final info = await _escribible(esquema, tabla);
    final valores = _limpiar(info, datos);
    for (final c in info.columnas) {
      final requerido = c.requerido && !c.tieneDefecto && !c.generada && c.editable;
      if (requerido && valores[c.nombre] == null) {
        throw ErrorDatos(422, 'Falta completar "${c.nombre}".');
      }
    }
    return _repo.crear(info, valores);
  }

  Future<void> actualizar(String esquema, String tabla, String claveCodificada, Map<String, Object?> datos) async {
    final info = await _escribible(esquema, tabla);
    final valores = _limpiar(info, datos)..removeWhere((k, _) => info.columna(k)!.esClave);
    await _repo.actualizar(info, decodificarClave(claveCodificada), valores);
  }

  Future<String> eliminar(String esquema, String tabla, String claveCodificada) async {
    final info = await _escribible(esquema, tabla);
    return _repo.eliminar(info, decodificarClave(claveCodificada));
  }

  Future<TablaInfo> _escribible(String esquema, String tabla) async {
    final info = await _repo.tabla(esquema, tabla);
    if (info.soloLectura) {
      throw ErrorDatos(403, 'La tabla ${info.nombreCompleto} es de solo lectura.');
    }
    return info;
  }

  /// Convierte lo recibido a texto (o nulo) y descarta columnas desconocidas
  /// o que no se pueden editar.
  Map<String, Object?> _limpiar(TablaInfo info, Map<String, Object?> datos) {
    final valores = <String, Object?>{};
    for (final e in datos.entries) {
      final c = info.columna(e.key);
      if (c == null) throw ErrorDatos(400, 'La columna "${e.key}" no existe en ${info.nombreCompleto}.');
      if (!c.editable) continue;
      final v = e.value;
      final texto = switch (v) {
        null => null,
        String() => v.trim().isEmpty ? null : v.trim(),
        Map() || List() => jsonEncode(v),
        _ => v.toString(),
      };
      if (c.esSecreta && texto == null) continue;
      if (c.tipo == 'json' && texto != null) {
        try {
          jsonDecode(texto);
        } on FormatException {
          throw ErrorDatos(422, 'El campo "${c.nombre}" debe ser JSON válido.');
        }
      }
      valores[c.nombre] = texto;
    }
    return valores;
  }

  /// La clave de un registro viaja en la URL como JSON en base64url,
  /// para soportar también claves de varias columnas.
  static Map<String, Object?> decodificarClave(String codificada) {
    try {
      final normalizada = base64Url.normalize(codificada);
      return (jsonDecode(utf8.decode(base64Url.decode(normalizada))) as Map).cast<String, Object?>();
    } on Object {
      throw ErrorDatos(400, 'La clave del registro no es válida.');
    }
  }
}
