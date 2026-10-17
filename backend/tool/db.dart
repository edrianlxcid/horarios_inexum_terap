// Herramienta de base de datos para desarrollo.
//
//   dart run tool/db.dart preparar    Crea la base y el usuario de la API, y aplica migraciones.
//   dart run tool/db.dart migrar      Aplica solo las migraciones pendientes.
//   dart run tool/db.dart semilla     Carga los datos ficticios (base vacía).
//   dart run tool/db.dart reiniciar   Borra la base y la vuelve a crear con datos ficticios.
//
// Lee la configuración del archivo .env de la raíz del proyecto.

import 'dart:io';

import 'package:backend/core/config.dart';
import 'package:backend/core/db/conexion.dart';
import 'package:backend/core/db/migrador.dart';
import 'package:postgres/postgres.dart';

import 'semilla/generador.dart';

Future<void> main(List<String> args) async {
  final comando = args.isEmpty ? 'ayuda' : args.first;
  final config = Config.cargar();
  try {
    switch (comando) {
      case 'preparar':
        await _preparar(config);
      case 'migrar':
        await _migrar(config);
      case 'semilla':
        await _semilla(config);
      case 'reiniciar':
        if (!config.esDesarrollo) {
          stderr.writeln('reiniciar solo está permitido con APP_ENV=development.');
          exit(1);
        }
        await _borrarBase(config);
        await _preparar(config);
        await _semilla(config);
      default:
        stdout.writeln('Uso: dart run tool/db.dart [preparar | migrar | semilla | reiniciar]');
    }
  } on Exception catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  } on Error catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}

final _identificador = RegExp(r'^[a-z_][a-z0-9_]*$');

String _validar(String nombre) {
  if (!_identificador.hasMatch(nombre)) {
    throw ArgumentError('Nombre no permitido: $nombre (solo minúsculas, números y _)');
  }
  return nombre;
}

String _literal(String texto) => "'${texto.replaceAll("'", "''")}'";

Future<void> _preparar(Config config) async {
  final base = _validar(config.dbNombre);
  final usuario = _validar(config.dbAppUsuario);

  final admin = await conectarAdmin(config, baseDatos: 'postgres');
  try {
    final existe = await admin.execute(
      Sql.named('SELECT 1 FROM pg_database WHERE datname = @n'),
      parameters: {'n': base},
    );
    if (existe.isEmpty) {
      await admin.execute('CREATE DATABASE $base');
      stdout.writeln('✓ Base de datos $base creada');
    }
    final rol = await admin.execute(
      Sql.named('SELECT 1 FROM pg_roles WHERE rolname = @n'),
      parameters: {'n': usuario},
    );
    final accion = rol.isEmpty ? 'CREATE' : 'ALTER';
    await admin.execute('$accion ROLE $usuario LOGIN PASSWORD ${_literal(config.dbAppPassword)}');
    stdout.writeln('✓ Usuario $usuario listo (permisos mínimos)');
  } finally {
    await admin.close();
  }

  await _migrar(config);

  final db = await conectarAdmin(config);
  try {
    await db.execute('GRANT ismart_app TO $usuario');
    await db.execute('REVOKE CONNECT, TEMPORARY ON DATABASE $base FROM PUBLIC');
    await db.execute('GRANT CONNECT, TEMPORARY ON DATABASE $base TO ismart_app, ismart_reportes, $usuario');
    stdout.writeln('✓ Permisos asignados');
  } finally {
    await db.close();
  }
}

Future<void> _migrar(Config config) async {
  final db = await conectarAdmin(config);
  try {
    final aplicadas = await Migrador(db, 'db/migrations').aplicarPendientes();
    if (aplicadas.isEmpty) {
      stdout.writeln('✓ Migraciones al día');
    } else {
      for (final v in aplicadas) {
        stdout.writeln('✓ Migración $v aplicada');
      }
    }
  } finally {
    await db.close();
  }
}

Future<void> _semilla(Config config) async {
  final db = await conectarAdmin(config);
  try {
    final hay = await db.execute('SELECT count(*) FROM personas.pacientes');
    if ((hay.first.first! as int) > 0) {
      throw StateError('La base ya tiene datos. Usa "reiniciar" para empezar de cero.');
    }
    stdout.writeln('… Generando datos ficticios (puede tardar un minuto)');
    final reloj = Stopwatch()..start();
    final resumen = await cargarDatosFicticios(
      db,
      llave: config.llaveCifrado,
      passwordUsuarios: config.passwordSemilla,
    );
    stdout.writeln('✓ Datos ficticios cargados en ${reloj.elapsed.inSeconds} s');
    resumen.forEach((empresa, datos) {
      stdout.writeln('  $empresa');
      datos.forEach((k, v) => stdout.writeln('    ${v.toString().padLeft(6)}  $k'));
    });
  } finally {
    await db.close();
  }
}

Future<void> _borrarBase(Config config) async {
  final base = _validar(config.dbNombre);
  final admin = await conectarAdmin(config, baseDatos: 'postgres');
  try {
    await admin.execute('DROP DATABASE IF EXISTS $base WITH (FORCE)');
    stdout.writeln('✓ Base de datos $base borrada');
  } finally {
    await admin.close();
  }
}
