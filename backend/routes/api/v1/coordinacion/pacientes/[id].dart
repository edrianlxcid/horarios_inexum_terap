import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/coordinacion/pacientes/{id} → ficha completa (cédula incluida; queda en la bitácora).
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    return Response.json(body: await context.read<Dependencias>().coordinacion.paciente(context.read<Sesion>(), id));
  });
}
