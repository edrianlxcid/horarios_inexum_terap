import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/admin/datos/tablas → tablas de configuración que administra la empresa.
Future<Response> onRequest(RequestContext context) {
  final s = context.read<Sesion>();
  return rutaTablas(context, context.read<Dependencias>().datosAdministracion, (empresaId: s.empresaId, usuarioId: s.usuarioId));
}
