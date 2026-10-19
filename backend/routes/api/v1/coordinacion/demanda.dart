import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/coordinacion/demanda {paciente_id, nivel_id, motivo}
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final d = await cuerpoJson(context);
    await context.read<Dependencias>().coordinacion.pacientes.clasificarDemanda(
          context.read<Sesion>(),
          pacienteId: requerido<String>(d, 'paciente_id'),
          nivelId: requerido<String>(d, 'nivel_id'),
          motivo: requerido<String>(d, 'motivo'),
        );
    return Response.json(statusCode: 201, body: {'resultado': 'demanda clasificada'});
  });
}
