import 'dart:io';

import 'package:backend/core/config.dart';
import 'package:backend/core/db/conexion.dart';
import 'package:backend/modules/herramienta_datos/datos_repositorio.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

final Config _config = Config.cargar();
final Pool<void> _pool = crearPoolApp(_config);
final DatosServicio _datos = DatosServicio(DatosRepositorio(_pool, _config.llaveCifrado));

/// Middleware raíz: CORS para la app web y dependencias compartidas.
Handler middleware(Handler handler) {
  return handler
      .use(provider<DatosServicio>((_) => _datos))
      .use(provider<Config>((_) => _config))
      .use(_cors());
}

/// Solo acepta llamadas desde la app en localhost durante el desarrollo.
Middleware _cors() {
  return (handler) {
    return (context) async {
      final origen = context.request.headers['origin'];
      final permitido = origen != null && _esLocal(origen);
      final cabeceras = {
        if (permitido) 'Access-Control-Allow-Origin': origen,
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Vary': 'Origin',
      };
      if (context.request.method == HttpMethod.options) {
        return Response(statusCode: HttpStatus.noContent, headers: cabeceras);
      }
      final respuesta = await handler(context);
      return respuesta.copyWith(headers: {...respuesta.headers, ...cabeceras});
    };
  };
}

bool _esLocal(String origen) {
  final uri = Uri.tryParse(origen);
  return uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1');
}
