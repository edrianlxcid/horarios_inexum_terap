import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/coordinacion/disponibilidad?profesional=&fecha=AAAA-MM-DD → horas del día y su estado.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final q = context.request.uri.queryParameters;
    final profesional = q['profesional'];
    final fecha = q['fecha'];
    if (profesional == null || fecha == null) {
      return respuestaError(400, 'Indica el terapeuta y la fecha.');
    }
    return Response.json(
      body: await context.read<Dependencias>().coordinacion.disponibilidad(context.read<Sesion>(), profesional, fecha),
    );
  });
}
