import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/terapeuta/pacientes/{id}/tareas {titulo, descripcion, fecha_limite}
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().terapeuta.asignarTarea(
          context.read<Sesion>(),
          id,
          titulo: requerido<String>(d, 'titulo'),
          descripcion: d['descripcion'] as String?,
          fechaLimite: d['fecha_limite'] as String?,
        );
    return Response.json(statusCode: 201, body: {'resultado': 'tarea asignada'});
  });
}
