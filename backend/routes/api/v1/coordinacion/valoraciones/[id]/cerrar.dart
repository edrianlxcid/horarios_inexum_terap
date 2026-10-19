import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/coordinacion/valoraciones/{id}/cerrar {resultado, conclusion, programa_recomendado_id}
/// Resultados: INICIAL → INGRESA_A_PROGRAMA | NO_REQUIERE; FINAL → ALTA | CONTINUA | DERIVADO.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    await context.read<Dependencias>().coordinacion.valoraciones.cerrar(context.read<Sesion>(), id, await cuerpoJson(context));
    return Response(statusCode: 204);
  });
}
