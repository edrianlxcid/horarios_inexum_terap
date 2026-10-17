import 'package:backend/core/dependencias.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:backend/modules/herramienta_datos/rutas_datos.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT    /api/dev/datos/tablas/{esquema}/{tabla}/{clave} → editar
/// DELETE /api/dev/datos/tablas/{esquema}/{tabla}/{clave} → archivar (o borrar)
///
/// {clave} es el JSON de la clave primaria codificado en base64url.
Future<Response> onRequest(RequestContext context, String esquema, String tabla, String clave) => rutaRegistro(
      context,
      context.read<Dependencias>().datosDesarrollo,
      context.read<ContextoDatos>(),
      esquema,
      tabla,
      clave,
    );
