import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET  /api/v1/coordinacion/profesionales?q&area&sede → profesionales con su carga de la semana.
/// POST /api/v1/coordinacion/profesionales {cedula, nombres, apellidos, profesion, telefono, email,
///      fecha_ingreso, especialidades:[id], jornadas:[{dia, sede_id, inicio, fin}], pausas:[{dia, inicio, fin, tipo}]}
Future<Response> onRequest(RequestContext context) async {
  final servicio = context.read<Dependencias>().coordinacion.profesionales;
  final sesion = context.read<Sesion>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.get:
        final q = context.request.uri.queryParameters;
        return Response.json(body: await servicio.lista(sesion, q: q['q'] ?? '', area: q['area'], sede: q['sede']));
      case HttpMethod.post:
        final creado = await servicio.crear(sesion, await cuerpoJson(context));
        return Response.json(statusCode: 201, body: creado);
      default:
        return metodoNoPermitido();
    }
  });
}
