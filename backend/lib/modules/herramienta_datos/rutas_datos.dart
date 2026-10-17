import 'dart:io';

import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';

/// Manejadores compartidos por la herramienta de desarrollo (/api/dev/datos)
/// y la pantalla de Administración (/api/v1/admin/datos).

Future<Response> rutaTablas(RequestContext context, DatosServicio servicio, ContextoDatos ctx) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async => Response.json(body: await servicio.tablas(ctx)));
}

Future<Response> rutaFilas(
  RequestContext context,
  DatosServicio servicio,
  ContextoDatos ctx,
  String esquema,
  String tabla,
) {
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.get:
        final p = context.request.uri.queryParameters;
        return Response.json(
          body: await servicio.filas(
            ctx,
            esquema,
            tabla,
            q: p['q'] ?? '',
            pagina: int.tryParse(p['pagina'] ?? '') ?? 1,
            tamano: int.tryParse(p['tamano'] ?? '') ?? 25,
          ),
        );
      case HttpMethod.post:
        final clave = await servicio.crear(ctx, esquema, tabla, await cuerpoJson(context));
        return Response.json(statusCode: HttpStatus.created, body: {'clave': clave});
      default:
        return metodoNoPermitido();
    }
  });
}

Future<Response> rutaRegistro(
  RequestContext context,
  DatosServicio servicio,
  ContextoDatos ctx,
  String esquema,
  String tabla,
  String clave,
) {
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.put:
        await servicio.actualizar(ctx, esquema, tabla, clave, await cuerpoJson(context));
        return Response.json(body: {'resultado': 'actualizado'});
      case HttpMethod.delete:
        return Response.json(body: {'resultado': await servicio.eliminar(ctx, esquema, tabla, clave)});
      default:
        return metodoNoPermitido();
    }
  });
}

Future<Response> rutaOpciones(
  RequestContext context,
  DatosServicio servicio,
  ContextoDatos ctx,
  String esquema,
  String tabla,
) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final q = context.request.uri.queryParameters['q'] ?? '';
    return Response.json(body: await servicio.opciones(ctx, esquema, tabla, q));
  });
}
