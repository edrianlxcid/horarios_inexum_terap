import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/familia/hijos → pacientes que representa el usuario.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    return Response.json(body: await context.read<Dependencias>().familias.hijos(context.read<Sesion>()));
  });
}
