import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/gerencia/bonos?periodo=AAAA-MM
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final periodo = context.request.uri.queryParameters['periodo'];
    return Response.json(body: await context.read<Dependencias>().gerencia.bonos(context.read<Sesion>(), periodo: periodo));
  });
}
