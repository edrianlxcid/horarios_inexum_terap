import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/auth/login {email, password} → tokens y empresas a las que pertenece.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    final sesion = await context.read<Dependencias>().auth.iniciarSesion(
          requerido<String>(d, 'email'),
          requerido<String>(d, 'password'),
          dispositivo: context.request.headers['user-agent'],
        );
    return Response.json(body: sesion);
  });
}
