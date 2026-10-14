import 'dart:io';

import 'package:postgres/postgres.dart';

/// Aplica en orden los archivos `.sql` de una carpeta y recuerda cuáles ya se
/// aplicaron en la tabla `public.schema_migraciones`.
///
/// Una migración aplicada no se edita: si su contenido cambia, el migrador se
/// detiene y pide crear un archivo nuevo.
class Migrador {
  Migrador(this._conexion, this._carpeta);

  final Connection _conexion;
  final String _carpeta;

  Future<List<String>> aplicarPendientes() async {
    await _conexion.execute('''
      CREATE TABLE IF NOT EXISTS public.schema_migraciones (
        version     text PRIMARY KEY,
        checksum    text NOT NULL,
        aplicada_en timestamptz NOT NULL DEFAULT now()
      )''');

    final filas = await _conexion.execute('SELECT version, checksum FROM public.schema_migraciones');
    final aplicadas = {for (final f in filas) f[0]! as String: f[1]! as String};

    final archivos = Directory(_carpeta)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => _nombre(a).compareTo(_nombre(b)));

    final nuevas = <String>[];
    for (final archivo in archivos) {
      final version = _nombre(archivo).replaceAll('.sql', '');
      final sql = await archivo.readAsString();
      final checksum = await _checksum(sql);

      final previo = aplicadas[version];
      if (previo != null) {
        if (previo != checksum) {
          throw StateError(
            'La migración $version cambió después de aplicarse. '
            'No edites migraciones aplicadas: crea un archivo nuevo.',
          );
        }
        continue;
      }

      await _conexion.runTx((tx) async {
        await tx.execute(sql, queryMode: QueryMode.simple);
        await tx.execute(
          Sql.named('INSERT INTO public.schema_migraciones (version, checksum) VALUES (@v, @c)'),
          parameters: {'v': version, 'c': checksum},
        );
      });
      nuevas.add(version);
    }
    return nuevas;
  }

  Future<String> _checksum(String sql) async {
    final r = await _conexion.execute(Sql.named('SELECT md5(@s:text)'), parameters: {'s': sql});
    return r.first.first! as String;
  }

  static String _nombre(File f) => f.uri.pathSegments.last;
}
