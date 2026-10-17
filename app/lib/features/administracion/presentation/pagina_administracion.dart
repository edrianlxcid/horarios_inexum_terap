import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../herramienta_datos/presentation/pagina_datos.dart';

/// Administración: configuración de la empresa (sedes, programas, terapeutas,
/// jornadas, usuarios y roles, bonos). Reutiliza la herramienta de datos,
/// pero la API solo le muestra las tablas de configuración de su empresa.
class PaginaAdministracion extends StatelessWidget {
  const PaginaAdministracion({super.key});

  @override
  Widget build(BuildContext context) {
    return PaginaDatos(
      api: Dependencias.de(context).administracion,
      titulo: 'Administración',
      subtitulo: 'Configuración de la empresa',
      tablaInicial: 'organizacion.sedes',
    );
  }
}
