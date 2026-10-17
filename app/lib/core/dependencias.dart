import 'package:flutter/widgets.dart';

import '../features/coordinacion/data/coordinacion_api.dart';
import '../features/familias/data/familias_api.dart';
import '../features/gerencia/data/gerencia_api.dart';
import '../features/herramienta_datos/data/datos_api.dart';
import '../features/terapeuta/data/terapeuta_api.dart';
import 'auth/sesion_controlador.dart';
import 'network/cliente_api.dart';

/// Servicios de la app, creados una sola vez y disponibles para todas las pantallas
/// con `Dependencias.de(context)`.
class Dependencias extends InheritedWidget {
  Dependencias({super.key, required this.cliente, required super.child})
      : sesion = SesionControlador(cliente),
        terapeuta = TerapeutaApi(cliente),
        familias = FamiliasApi(cliente),
        coordinacion = CoordinacionApi(cliente),
        gerencia = GerenciaApi(cliente),
        administracion = DatosApi(cliente, base: '/api/v1/admin/datos'),
        datosDesarrollo = DatosApi(cliente);

  final ClienteApi cliente;
  final SesionControlador sesion;
  final TerapeutaApi terapeuta;
  final FamiliasApi familias;
  final CoordinacionApi coordinacion;
  final GerenciaApi gerencia;
  final DatosApi administracion;
  final DatosApi datosDesarrollo;

  static Dependencias de(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Dependencias>() ?? (throw StateError('Falta Dependencias en el árbol'));

  @override
  bool updateShouldNotify(Dependencias oldWidget) => false;
}
