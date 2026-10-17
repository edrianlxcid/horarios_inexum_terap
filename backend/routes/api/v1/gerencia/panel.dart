import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/gerencia/panel?fecha=AAAA-MM-DD → indicadores del día, evolución y metas.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final fecha = context.request.uri.queryParameters['fecha'];
    return Response.json(body: await context.read<Dependencias>().gerencia.panel(context.read<Sesion>(), fecha: fecha));
  });
}
