import 'dart:io';

import 'package:backend/core/dependencias.dart';
import 'package:dart_frog/dart_frog.dart';

final Dependencias _dependencias = Dependencias.crear();

/// Middleware raíz: CORS para la app web y los servicios compartidos.
Handler middleware(Handler handler) {
  return handler.use(provider<Dependencias>((_) => _dependencias)).use(_cors());
}

/// Solo acepta llamadas del navegador desde la app en localhost durante el desarrollo.
Middleware _cors() {
  return (handler) {
    return (context) async {
      final origen = context.request.headers['origin'];
      final permitido = origen != null && _esLocal(origen);
      final cabeceras = {
        if (permitido) 'Access-Control-Allow-Origin': origen,
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Empresa-Id',
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
