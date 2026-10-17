import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/coordinacion/solicitudes?estado=PENDIENTE&area
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final q = context.request.uri.queryParameters;
    return Response.json(
      body: await context.read<Dependencias>().coordinacion.solicitudes(
            context.read<Sesion>(),
            estado: q['estado'] ?? 'PENDIENTE',
            area: q['area'],
          ),
    );
  });
}
