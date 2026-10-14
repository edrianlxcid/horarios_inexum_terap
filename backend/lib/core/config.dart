import 'dart:io';

import 'package:dotenv/dotenv.dart';

/// Configuración leída del archivo `.env` de la raíz del proyecto
/// (o de las variables de entorno del sistema en producción).
class Config {
  Config._(this._env);

  /// Busca `.env` en la carpeta actual y en la superior (la raíz del proyecto
  /// cuando se ejecuta desde `backend/`).
  factory Config.cargar() {
    final env = DotEnv(includePlatformEnvironment: true, quiet: true);
    for (final ruta in const ['.env', '../.env']) {
      if (File(ruta).existsSync()) {
        env.load([ruta]);
        break;
      }
    }
    return Config._(env);
  }

  final DotEnv _env;

  String _requerido(String clave) {
    final valor = _env[clave];
    if (valor == null || valor.isEmpty) {
      throw StateError('Falta la variable $clave en el archivo .env');
    }
    return valor;
  }

  bool get esDesarrollo => _env['APP_ENV'] == 'development';

  String get dbHost => _env['DB_HOST'] ?? 'localhost';
  int get dbPuerto => int.parse(_env['DB_PORT'] ?? '5432');
  String get dbNombre => _requerido('DB_NAME');

  String get dbAdminUsuario => _requerido('DB_ADMIN_USER');
  String get dbAdminPassword => _requerido('DB_ADMIN_PASSWORD');

  String get dbAppUsuario => _requerido('DB_APP_USER');
  String get dbAppPassword => _requerido('DB_APP_PASSWORD');

  String get llaveCifrado {
    final llave = _requerido('DB_ENCRYPTION_KEY');
    if (llave.length < 32) {
      throw StateError('DB_ENCRYPTION_KEY debe tener al menos 32 caracteres');
    }
    return llave;
  }

  String get passwordSemilla => _requerido('DEV_SEED_PASSWORD');
}
