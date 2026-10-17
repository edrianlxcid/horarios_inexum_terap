import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/familia/tareas/{id}/completar {comentario}
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().familias.completarTarea(context.read<Sesion>(), id, d['comentario'] as String?);
    return Response.json(body: {'resultado': 'tarea completada'});
  });
}
