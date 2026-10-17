import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/terapeuta/participantes/{id}/nota → nota y objetivos.
/// PUT /api/v1/terapeuta/participantes/{id}/nota {contenido, resumen_familia, firmar, avances:[{objetivo_id, nivel}]}
Future<Response> onRequest(RequestContext context, String id) async {
  final servicio = context.read<Dependencias>().terapeuta;
  final sesion = context.read<Sesion>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.get:
        return Response.json(body: await servicio.nota(sesion, id));
      case HttpMethod.put:
        final d = await cuerpoJson(context);
        await servicio.guardarNota(
          sesion,
          id,
          contenido: requerido<String>(d, 'contenido'),
          resumenFamilia: d['resumen_familia'] as String?,
          firmar: d['firmar'] == true,
          avances: ((d['avances'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        );
        return Response.json(body: {'resultado': d['firmar'] == true ? 'nota firmada' : 'nota guardada'});
      default:
        return metodoNoPermitido();
    }
  });
}
