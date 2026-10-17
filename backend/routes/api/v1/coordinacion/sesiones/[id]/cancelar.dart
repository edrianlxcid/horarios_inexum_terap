import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/coordinacion/sesiones/{id}/cancelar {motivo}
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().coordinacion.cancelarSesion(
          context.read<Sesion>(),
          id,
          requerido<String>(d, 'motivo'),
        );
    return Response.json(body: {'resultado': 'sesión cancelada'});
  });
}
