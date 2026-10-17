import 'package:backend/core/db/base_datos.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/dev/datos/empresas → empresas para elegir en la herramienta de datos.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final empresas = await context.read<Dependencias>().db.sinEmpresa(
          (tx) => filas(tx, 'SELECT id::text, nombre, rubro, empresa_matriz_id IS NULL AS es_matriz '
              'FROM organizacion.empresas ORDER BY empresa_matriz_id NULLS FIRST, nombre'),
        );
    return Response.json(body: empresas);
  });
}
