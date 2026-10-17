import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/familia/hijos/{id} → sesiones, progreso, tareas, contrato vigente y evaluaciones pendientes.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    return Response.json(body: await context.read<Dependencias>().familias.resumen(context.read<Sesion>(), id));
  });
}
