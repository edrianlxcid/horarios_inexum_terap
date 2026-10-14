import 'dart:io';

import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/dev/datos/tablas → tablas y columnas de todos los módulos.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  return conErrores(() async {
    final tablas = await context.read<DatosServicio>().tablas();
    return Response.json(body: tablas);
  });
}
