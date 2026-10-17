import 'dart:convert';

import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/herramienta_datos/datos_repositorio.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Empresa y usuario con los que se ejecuta una operación.
typedef ContextoDatos = ({String empresaId, String? usuarioId});

/// Edición genérica de tablas. Se usa en dos lugares:
/// - la herramienta de desarrollo (todas las tablas), y
/// - la pantalla de Administración (solo [permitidas], algunas en [soloLectura]).
/// Las reglas de negocio las sigue validando la base de datos.
class DatosServicio {
  DatosServicio(this._db, this._llave, {this.permitidas, this.soloLectura = const {}});

  final BaseDatos _db;
  final String _llave;

  /// Tablas visibles (esquema.tabla). Null = todas.
  final Set<String>? permitidas;

  /// Tablas que se pueden ver pero no editar.
  final Set<String> soloLectura;

  Future<T> _con<T>(ContextoDatos ctx, Future<T> Function(DatosRepositorio repo) accion) =>
      _db.enEmpresa(ctx.empresaId, (tx) => accion(DatosRepositorio(tx, _llave)), usuarioId: ctx.usuarioId);

  Future<List<Map<String, Object?>>> tablas(ContextoDatos ctx) => _con(ctx, (repo) async {
        return [
          for (final t in await repo.tablas())
            if (permitidas == null || permitidas!.contains(t.nombreCompleto))
              {...t.toJson(), if (soloLectura.contains(t.nombreCompleto)) 'soloLectura': true},
        ];
      });

  Future<Map<String, Object?>> filas(
    ContextoDatos ctx,
    String esquema,
    String tabla, {
    String q = '',
    int pagina = 1,
    int tamano = 25,
  }) =>
      _con(ctx, (repo) async {
        final info = await _visible(repo, esquema, tabla);
        return repo.filas(info, busqueda: q, pagina: pagina < 1 ? 1 : pagina, tamano: tamano.clamp(5, 100));
      });

  Future<List<Map<String, Object?>>> opciones(ContextoDatos ctx, String esquema, String tabla, String q) =>
      _con(ctx, (repo) async => repo.opciones(await repo.tabla(esquema, tabla), q));

  Future<Map<String, Object?>> crear(ContextoDatos ctx, String esquema, String tabla, Map<String, Object?> datos) =>
      _con(ctx, (repo) async {
        final info = await _escribible(repo, esquema, tabla);
        final valores = _limpiar(info, datos);
        for (final c in info.columnas) {
          final requerido = c.requerido && !c.tieneDefecto && !c.generada && c.editable;
          if (requerido && valores[c.nombre] == null) {
            throw ErrorDatos(422, 'Falta completar "${c.nombre}".');
          }
        }
        return repo.crear(info, valores);
      });

  Future<void> actualizar(
    ContextoDatos ctx,
    String esquema,
    String tabla,
    String claveCodificada,
    Map<String, Object?> datos,
  ) =>
      _con(ctx, (repo) async {
        final info = await _escribible(repo, esquema, tabla);
        final valores = _limpiar(info, datos)..removeWhere((k, _) => info.columna(k)!.esClave);
        await repo.actualizar(info, decodificarClave(claveCodificada), valores);
      });

  Future<String> eliminar(ContextoDatos ctx, String esquema, String tabla, String claveCodificada) =>
      _con(ctx, (repo) async {
        final info = await _escribible(repo, esquema, tabla);
        return repo.eliminar(info, decodificarClave(claveCodificada));
      });

  Future<TablaInfo> _visible(DatosRepositorio repo, String esquema, String tabla) async {
    final info = await repo.tabla(esquema, tabla);
    if (permitidas != null && !permitidas!.contains(info.nombreCompleto)) {
      throw ErrorDatos(404, 'No existe la tabla $esquema.$tabla');
    }
    return info;
  }

  Future<TablaInfo> _escribible(DatosRepositorio repo, String esquema, String tabla) async {
    final info = await _visible(repo, esquema, tabla);
    if (info.soloLectura || soloLectura.contains(info.nombreCompleto)) {
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
