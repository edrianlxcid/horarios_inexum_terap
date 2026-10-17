import 'package:backend/core/auth/sesion.dart';
import 'package:postgres/postgres.dart';

/// Punto único de acceso a la base para los módulos de la API.
///
/// Cada operación corre en una transacción que fija la empresa activa y el
/// usuario (app.empresa_id y app.usuario_id). Con eso PostgreSQL aplica el
/// aislamiento por empresa y la bitácora sabe quién hizo cada cambio.
class BaseDatos {
  BaseDatos(this._pool);

  final Pool<void> _pool;

  Future<T> conSesion<T>(Sesion sesion, Future<T> Function(TxSession tx) accion) =>
      enEmpresa(sesion.empresaId, accion, usuarioId: sesion.usuarioId);

  Future<T> enEmpresa<T>(String? empresaId, Future<T> Function(TxSession tx) accion, {String? usuarioId}) {
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named("SELECT set_config('app.empresa_id', @e, true), set_config('app.usuario_id', @u, true)"),
        parameters: {'e': empresaId ?? '', 'u': usuarioId ?? ''},
      );
      return accion(tx);
    });
  }

  /// Para operaciones previas a conocer la empresa (inicio de sesión).
  Future<T> sinEmpresa<T>(Future<T> Function(TxSession tx) accion) => enEmpresa(null, accion);
}

/// Ejecuta pasando solo los parámetros que aparecen en el SQL
/// (el driver rechaza parámetros sobrantes).
Future<Result> consultar(Session db, String sql, [Map<String, Object?> parametros = const {}]) {
  final usados = {
    for (final e in parametros.entries)
      if (RegExp('@${e.key}\\b').hasMatch(sql)) e.key: e.value,
  };
  return db.execute(Sql.named(sql), parameters: usados);
}

/// Filas como mapas columna → valor.
Future<List<Map<String, dynamic>>> filas(Session db, String sql, [Map<String, Object?> parametros = const {}]) async {
  final r = await consultar(db, sql, parametros);
  return [for (final f in r) f.toColumnMap()];
}

/// Primera fila o null.
Future<Map<String, dynamic>?> fila(Session db, String sql, [Map<String, Object?> parametros = const {}]) async {
  final r = await filas(db, sql, parametros);
  return r.isEmpty ? null : r.first;
}
