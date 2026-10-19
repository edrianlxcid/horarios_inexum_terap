import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET  /api/v1/coordinacion/pacientes?q&area&sede&estado&profesional&programa&pagina
///      → {total, pagina, tamano, filas}: cada fila con contrato, programas, avance y representante.
/// POST /api/v1/coordinacion/pacientes {nombres, apellidos, fecha_nacimiento, sede_id, ..., representante:{...}}
Future<Response> onRequest(RequestContext context) async {
  final servicio = context.read<Dependencias>().coordinacion.pacientes;
  final sesion = context.read<Sesion>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.get:
        final q = context.request.uri.queryParameters;
        return Response.json(
          body: await servicio.lista(
            sesion,
            q: q['q'] ?? '',
            area: q['area'],
            sede: q['sede'],
            estado: q['estado'],
            profesional: q['profesional'],
            programa: q['programa'],
            pagina: int.tryParse(q['pagina'] ?? '') ?? 1,
          ),
        );
      case HttpMethod.post:
        final creado = await servicio.crear(sesion, await cuerpoJson(context));
        return Response.json(statusCode: 201, body: creado);
      default:
        return metodoNoPermitido();
    }
  });
}
