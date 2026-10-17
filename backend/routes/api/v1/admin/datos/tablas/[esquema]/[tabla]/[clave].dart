import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT    /api/v1/admin/datos/tablas/{esquema}/{tabla}/{clave} → editar
/// DELETE /api/v1/admin/datos/tablas/{esquema}/{tabla}/{clave} → archivar (o borrar)
Future<Response> onRequest(RequestContext context, String esquema, String tabla, String clave) {
  final s = context.read<Sesion>();
  return rutaRegistro(
    context,
    context.read<Dependencias>().datosAdministracion,
    (empresaId: s.empresaId, usuarioId: s.usuarioId),
    esquema,
    tabla,
    clave,
  );
}
