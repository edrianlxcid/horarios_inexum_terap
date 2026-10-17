import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/coordinacion/contexto → sedes, áreas, terapeutas y programas de su alcance.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    return Response.json(body: await context.read<Dependencias>().coordinacion.contexto(context.read<Sesion>()));
  });
}
