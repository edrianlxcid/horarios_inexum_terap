import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/familia/solicitudes {participante_id, tipo, motivo, propuesta_inicio}
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().familias.solicitarCambio(
          context.read<Sesion>(),
          participanteId: requerido<String>(d, 'participante_id'),
          tipo: requerido<String>(d, 'tipo'),
          motivo: requerido<String>(d, 'motivo'),
          propuesta: d['propuesta_inicio'] as String?,
        );
    return Response.json(statusCode: 201, body: {'resultado': 'solicitud enviada'});
  });
}
