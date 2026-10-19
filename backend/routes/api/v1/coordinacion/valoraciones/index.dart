import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/coordinacion/valoraciones
///      {paciente_id, tipo: INICIAL | FINAL, especialidades: [{sub_area_id, sesiones}], matricula_id?}
///      → abre la valoración con sus sesiones previstas (de 1 a 20 en total).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final creada = await context.read<Dependencias>().coordinacion.valoraciones.abrir(context.read<Sesion>(), await cuerpoJson(context));
    return Response.json(statusCode: 201, body: creada);
  });
}
