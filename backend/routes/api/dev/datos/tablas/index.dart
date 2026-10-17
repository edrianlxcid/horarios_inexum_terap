import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/dev/datos/tablas → tablas y columnas de todos los módulos.
Future<Response> onRequest(RequestContext context) =>
    rutaTablas(context, context.read<Dependencias>().datosDesarrollo, context.read<ContextoDatos>());
