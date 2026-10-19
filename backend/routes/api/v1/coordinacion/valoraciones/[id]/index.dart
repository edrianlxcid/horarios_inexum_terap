import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT    /api/v1/coordinacion/valoraciones/{id} {especialidades: [{sub_area_id, sesiones}]} → ajusta lo previsto.
/// DELETE /api/v1/coordinacion/valoraciones/{id} → anula una valoración abierta por error (sin sesiones).
Future<Response> onRequest(RequestContext context, String id) async {
  final servicio = context.read<Dependencias>().coordinacion.valoraciones;
  final sesion = context.read<Sesion>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.put:
        await servicio.ajustar(sesion, id, await cuerpoJson(context));
        return Response(statusCode: 204);
      case HttpMethod.delete:
        await servicio.cancelar(sesion, id);
        return Response(statusCode: 204);
      default:
        return metodoNoPermitido();
    }
  });
}
