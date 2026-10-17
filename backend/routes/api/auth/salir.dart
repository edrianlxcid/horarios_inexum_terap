import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/auth/salir {token_renovacion} → cierra la sesión en este dispositivo.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().auth.cerrarSesion(requerido<String>(d, 'token_renovacion'));
    return Response.json(body: {'resultado': 'sesión cerrada'});
  });
}
