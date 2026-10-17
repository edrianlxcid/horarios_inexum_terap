import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET  /api/dev/datos/tablas/{esquema}/{tabla}?q=&pagina=&tamano=  → filas
/// POST /api/dev/datos/tablas/{esquema}/{tabla}                     → crear
Future<Response> onRequest(RequestContext context, String esquema, String tabla) => rutaFilas(
      context,
      context.read<Dependencias>().datosDesarrollo,
      context.read<ContextoDatos>(),
      esquema,
      tabla,
    );
