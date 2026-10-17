import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/coordinacion/sesiones {paciente_id, profesional_id, inicio, tipo, matricula_id}
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final resultado = await context.read<Dependencias>().coordinacion.agendar(
          context.read<Sesion>(),
          await cuerpoJson(context),
        );
    return Response.json(statusCode: 201, body: resultado);
  });
}
