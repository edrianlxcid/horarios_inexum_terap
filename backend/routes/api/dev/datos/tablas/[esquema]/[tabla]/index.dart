import 'dart:io';

import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET  /api/dev/datos/tablas/{esquema}/{tabla}?q=&pagina=&tamano=  → filas
/// POST /api/dev/datos/tablas/{esquema}/{tabla}                     → crear
Future<Response> onRequest(RequestContext context, String esquema, String tabla) {
  final servicio = context.read<DatosServicio>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.get:
        final p = context.request.uri.queryParameters;
        final pagina = await servicio.filas(
          esquema,
          tabla,
          q: p['q'] ?? '',
          pagina: int.tryParse(p['pagina'] ?? '') ?? 1,
          tamano: int.tryParse(p['tamano'] ?? '') ?? 25,
        );
        return Response.json(body: pagina);
      case HttpMethod.post:
        final datos = (await context.request.json() as Map).cast<String, Object?>();
        final clave = await servicio.crear(esquema, tabla, datos);
        return Response.json(statusCode: HttpStatus.created, body: {'clave': clave});
      default:
        return Response(statusCode: HttpStatus.methodNotAllowed);
    }
  });
}
