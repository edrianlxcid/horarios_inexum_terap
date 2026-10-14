import 'package:backend/core/config.dart';
import 'package:postgres/postgres.dart';

/// Pool de conexiones que usa la API, con el usuario de permisos mínimos.
/// Reutiliza conexiones en lugar de abrir una por petición.
Pool<void> crearPoolApp(Config config) {
  return Pool.withEndpoints(
    [
      Endpoint(
        host: config.dbHost,
        port: config.dbPuerto,
        database: config.dbNombre,
        username: config.dbAppUsuario,
        password: config.dbAppPassword,
      ),
    ],
    settings: const PoolSettings(
      maxConnectionCount: 10,
      sslMode: SslMode.disable,
    ),
  );
}

/// Conexión con el superusuario. Solo para crear la base, aplicar
/// migraciones y cargar datos de prueba; nunca la usa la API.
Future<Connection> conectarAdmin(Config config, {String? baseDatos}) {
  return Connection.open(
    Endpoint(
      host: config.dbHost,
      port: config.dbPuerto,
      database: baseDatos ?? config.dbNombre,
      username: config.dbAdminUsuario,
      password: config.dbAdminPassword,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
}
