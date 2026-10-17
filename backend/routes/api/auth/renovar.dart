import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/auth/renovar {token_renovacion} → tokens nuevos (el anterior deja de servir).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    final sesion = await context.read<Dependencias>().auth.renovar(requerido<String>(d, 'token_renovacion'));
    return Response.json(body: sesion);
  });
}
