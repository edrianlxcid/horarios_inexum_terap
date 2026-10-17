import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/familia/evaluaciones {matricula_id, profesional_id, puntaje, comentario}
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().familias.evaluar(
          context.read<Sesion>(),
          matriculaId: requerido<String>(d, 'matricula_id'),
          profesionalId: requerido<String>(d, 'profesional_id'),
          puntaje: requerido<int>(d, 'puntaje'),
          comentario: d['comentario'] as String?,
        );
    return Response.json(statusCode: 201, body: {'resultado': 'evaluación registrada'});
  });
}
