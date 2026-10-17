import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/yo → usuario, empresa activa con sus roles y demás empresas.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final perfil = await context.read<Dependencias>().auth.perfil(context.read<Sesion>());
    return Response.json(body: perfil);
  });
}
