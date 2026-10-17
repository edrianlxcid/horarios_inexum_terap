import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/accesos_demo.dart';
import 'package:dart_frog/dart_frog.dart';

/// Acceso rápido de desarrollo para probar cada interfaz sin escribir contraseñas.
/// GET  /api/dev/accesos                → usuarios de prueba por empresa y rol
/// POST /api/dev/accesos {usuario_id}   → sesión de ese usuario (mismo formato que /api/auth/login)
Future<Response> onRequest(RequestContext context) async {
  final dep = context.read<Dependencias>();
  return conErrores(() async {
    switch (context.request.method) {
      case HttpMethod.get:
        return Response.json(body: await AccesosDemo(dep.db).listar());
      case HttpMethod.post:
        final d = await cuerpoJson(context);
        return Response.json(body: await dep.auth.sesionDeDesarrollo(requerido<String>(d, 'usuario_id')));
      default:
        return metodoNoPermitido();
    }
  });
}
