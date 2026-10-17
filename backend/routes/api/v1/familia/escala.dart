import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/familia/escala → escala con la que se evalúa al terapeuta.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async => Response.json(body: await context.read<Dependencias>().familias.escala()));
}
