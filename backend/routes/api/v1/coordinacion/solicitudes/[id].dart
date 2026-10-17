import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT /api/v1/coordinacion/solicitudes/{id} {estado: APROBADA | RECHAZADA}
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().coordinacion.resolverSolicitud(
          context.read<Sesion>(),
          id,
          requerido<String>(d, 'estado'),
        );
    return Response.json(body: {'resultado': 'solicitud resuelta'});
  });
}
