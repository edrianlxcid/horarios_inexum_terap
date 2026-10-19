import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/coordinacion/agenda?desde&hasta&area&sede&profesional
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final q = context.request.uri.queryParameters;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final sesiones = await context.read<Dependencias>().coordinacion.agenda.sesiones(
          context.read<Sesion>(),
          desde: q['desde'] ?? hoy,
          hasta: q['hasta'] ?? q['desde'] ?? hoy,
          area: q['area'],
          sede: q['sede'],
          profesional: q['profesional'],
        );
    return Response.json(body: sesiones);
  });
}
