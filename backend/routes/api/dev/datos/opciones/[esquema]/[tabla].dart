import 'dart:io';

import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/dev/datos/opciones/{esquema}/{tabla}?q= → registros para elegir
/// en un campo que referencia a esa tabla.
Future<Response> onRequest(RequestContext context, String esquema, String tabla) {
  if (context.request.method != HttpMethod.get) {
    return Future.value(Response(statusCode: HttpStatus.methodNotAllowed));
  }
  return conErrores(() async {
    final q = context.request.uri.queryParameters['q'] ?? '';
    final opciones = await context.read<DatosServicio>().opciones(esquema, tabla, q);
    return Response.json(body: opciones);
  });
}
