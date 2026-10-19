import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT /api/v1/coordinacion/participantes/{id} {observacion} → nota de coordinación de la cita.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) return metodoNoPermitido();
  return conErrores(() async {
    final datos = await cuerpoJson(context);
    await context.read<Dependencias>().coordinacion.agenda.observacion(context.read<Sesion>(), id, datos['observacion'] as String?);
    return Response(statusCode: 204);
  });
}
