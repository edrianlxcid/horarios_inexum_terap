import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/gerencia/recalcular → recalcula los indicadores de hoy.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return metodoNoPermitido();
  return conErrores(() async {
    final n = await context.read<Dependencias>().gerencia.recalcular(context.read<Sesion>());
    return Response.json(body: {'resultado': 'indicadores recalculados', 'valores': n});
  });
}
