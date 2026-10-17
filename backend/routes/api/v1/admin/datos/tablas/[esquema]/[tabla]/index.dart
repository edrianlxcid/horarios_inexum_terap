import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET  /api/v1/admin/datos/tablas/{esquema}/{tabla} → filas de la empresa activa
/// POST /api/v1/admin/datos/tablas/{esquema}/{tabla} → crear
Future<Response> onRequest(RequestContext context, String esquema, String tabla) {
  final s = context.read<Sesion>();
  return rutaFilas(
    context,
    context.read<Dependencias>().datosAdministracion,
    (empresaId: s.empresaId, usuarioId: s.usuarioId),
    esquema,
    tabla,
  );
}
