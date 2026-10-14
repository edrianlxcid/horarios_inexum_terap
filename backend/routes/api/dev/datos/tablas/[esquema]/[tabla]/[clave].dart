import 'dart:io';

import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT    /api/dev/datos/tablas/{esquema}/{tabla}/{clave} → editar
/// DELETE /api/dev/datos/tablas/{esquema}/{tabla}/{clave} → archivar (o borrar)
///
/// {clave} es el JSON de la clave primaria codificado en base64url.
Future<Response> onRequest(RequestContext context, String esquema, String tabla, String clave) {
  final servicio = context.read<DatosServicio>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.put:
        final datos = (await context.request.json() as Map).cast<String, Object?>();
        await servicio.actualizar(esquema, tabla, clave, datos);
        return Response.json(body: {'resultado': 'actualizado'});
      case HttpMethod.delete:
        final resultado = await servicio.eliminar(esquema, tabla, clave);
        return Response.json(body: {'resultado': resultado});
      default:
        return Response(statusCode: HttpStatus.methodNotAllowed);
    }
  });
}
