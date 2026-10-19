import 'package:flutter/material.dart';

import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';
import 'estudiantes/ficha_estudiante.dart';
import 'profesionales/ficha_profesional.dart';

/// Lo que comparten todas las pantallas de coordinación: el contexto
/// (sedes, áreas, terapeutas, programas) y el área elegida.
class AmbienteCoordinacion extends InheritedWidget {
  const AmbienteCoordinacion({super.key, required this.ctx, required this.area, required super.child});

  final ContextoCoordinacion ctx;
  final String? area;

  static AmbienteCoordinacion de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbienteCoordinacion>()!;

  @override
  bool updateShouldNotify(AmbienteCoordinacion anterior) => anterior.ctx != ctx || anterior.area != area;
}

// Las fichas se abren dentro del módulo actual: el menú lateral sigue a la
// vista y la flecha del encabezado vuelve a la pantalla anterior.

Future<void> abrirEstudiante(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FichaEstudiante(id: id)));

Future<void> abrirProfesional(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FichaProfesional(id: id)));

Tono tonoEstadoEstudiante(String? estado) => switch (estado) {
      'ACTIVO' => Tono.bien,
      'PROSPECTO' || 'CONGELADO' => Tono.alerta,
      'RETIRADO' => Tono.mal,
      _ => Tono.neutro,
    };

Tono tonoContrato(String? estado) => switch (estado) {
      'VIGENTE' => Tono.bien,
      'CONGELADO' || 'VENCIDO' => Tono.alerta,
      'ANULADO' => Tono.mal,
      _ => Tono.neutro,
    };

/// Barra inferior de un listado paginado.
class Paginacion extends StatelessWidget {
  const Paginacion({super.key, required this.texto, required this.pagina, required this.paginas, required this.alCambiar});

  final String texto;
  final int pagina;
  final int paginas;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(texto),
          const SizedBox(width: 16),
          IconButton(tooltip: 'Anterior', onPressed: pagina > 1 ? () => alCambiar(pagina - 1) : null, icon: const Icon(Icons.chevron_left)),
          Text('$pagina de $paginas'),
          IconButton(tooltip: 'Siguiente', onPressed: pagina < paginas ? () => alCambiar(pagina + 1) : null, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

/// Tabla que ocupa todo el ancho y se desplaza si no cabe.
class TablaDesplazable extends StatelessWidget {
  const TablaDesplazable({super.key, required this.tabla});

  final Widget tabla;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: tabla),
        ),
      ),
    );
  }
}

/// Desde este ancho el menú va a la izquierda; por debajo, abajo (celular).
const anchoEscritorio = 720.0;
