import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/terapeuta/agenda?desde=AAAA-MM-DD&hasta=AAAA-MM-DD (por defecto, hoy).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final q = context.request.uri.queryParameters;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final agenda = await context.read<Dependencias>().terapeuta.agenda(
          context.read<Sesion>(),
          q['desde'] ?? hoy,
          q['hasta'] ?? q['desde'] ?? hoy,
        );
    return Response.json(body: agenda);
  });
}
