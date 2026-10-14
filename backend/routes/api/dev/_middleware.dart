import 'dart:io';

import 'package:backend/core/config.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// Las rutas /api/dev son herramientas de desarrollo: solo funcionan con
/// APP_ENV=development y solo atienden pedidos hechos desde esta misma PC.
Handler middleware(Handler handler) {
  return (context) async {
    final config = context.read<Config>();
    final local = context.request.connectionInfo.remoteAddress.isLoopback;
    if (!config.esDesarrollo || !local) {
      return respuestaError(HttpStatus.forbidden, 'Herramienta disponible solo en desarrollo y desde esta PC.');
    }
    return handler(context);
  };
}
