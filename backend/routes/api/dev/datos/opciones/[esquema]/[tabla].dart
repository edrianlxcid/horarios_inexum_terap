import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/dev/datos/opciones/{esquema}/{tabla}?q= → registros para elegir
/// en un campo que referencia a esa tabla.
Future<Response> onRequest(RequestContext context, String esquema, String tabla) => rutaOpciones(
      context,
      context.read<Dependencias>().datosDesarrollo,
      context.read<ContextoDatos>(),
      esquema,
      tabla,
    );
