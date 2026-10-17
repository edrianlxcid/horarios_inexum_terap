import 'dart:io';

import 'package:backend/core/db/base_datos.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:dart_frog/dart_frog.dart';

String? _matriz;

/// Las rutas /api/dev son herramientas de desarrollo: solo funcionan con
/// APP_ENV=development y solo atienden pedidos hechos desde esta misma PC.
/// Trabajan sobre la empresa de la cabecera X-Empresa-Id (por defecto, la matriz).
Handler middleware(Handler handler) {
  return (context) async {
    final dep = context.read<Dependencias>();
    final local = context.request.connectionInfo.remoteAddress.isLoopback;
    if (!dep.config.esDesarrollo || !local) {
      return respuestaError(HttpStatus.forbidden, 'Herramienta disponible solo en desarrollo y desde esta PC.');
    }
    final cabecera = context.request.headers['x-empresa-id'];
    final empresa = (cabecera != null && cabecera.isNotEmpty)
        ? cabecera
        : _matriz ??= await dep.db.sinEmpresa((tx) async {
            final r = await fila(tx, 'SELECT id::text FROM organizacion.empresas '
                'WHERE empresa_matriz_id IS NULL ORDER BY creado_en LIMIT 1');
            return r?['id'] as String?;
          });
    if (empresa == null) return respuestaError(HttpStatus.conflict, 'No hay empresas cargadas.');
    final ContextoDatos ctx = (empresaId: empresa, usuarioId: null);
    return handler(context.provide<ContextoDatos>(() => ctx));
  };
}
