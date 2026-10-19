import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';
import 'agenda/vista_agenda.dart';
import 'coordinacion_comun.dart';
import 'estudiantes/vista_estudiantes.dart';
import 'horarios/vista_horarios.dart';
import 'profesionales/vista_profesionales.dart';
import 'solicitudes/vista_solicitudes.dart';

/// Módulos de coordinación, en el orden del menú.
enum ModuloCoordinacion {
  agenda('Agenda', Icons.today_outlined, Icons.today),
  estudiantes('Estudiantes', Icons.school_outlined, Icons.school),
  horarios('Horarios', Icons.calendar_view_week_outlined, Icons.calendar_view_week),
  profesionales('Profesionales', Icons.badge_outlined, Icons.badge),
  solicitudes('Solicitudes', Icons.inbox_outlined, Icons.inbox);

  const ModuloCoordinacion(this.titulo, this.icono, this.iconoActivo);

  final String titulo;
  final IconData icono;
  final IconData iconoActivo;

  Widget get paginaInicial => switch (this) {
        agenda => const VistaAgenda(),
        estudiantes => const VistaEstudiantes(),
        horarios => const VistaHorarios(),
        profesionales => const VistaProfesionales(),
        solicitudes => const VistaSolicitudes(),
      };
}

/// Coordinación: menú de módulos y, si coordina varias áreas, el área con la
/// que trabaja ("cambiar de interfaz"). Cada módulo tiene su propia
/// navegación: las fichas se abren dentro de él y se vuelve con la flecha.
class PaginaCoordinacion extends StatefulWidget {
  const PaginaCoordinacion({super.key});

  @override
  State<PaginaCoordinacion> createState() => _PaginaCoordinacionState();
}

class _PaginaCoordinacionState extends State<PaginaCoordinacion> {
  String? _area;
  var _modulo = ModuloCoordinacion.agenda;
  // Solo se construyen los módulos que ya se abrieron; al volver a uno,
  // conserva sus filtros y la ficha en la que estaba.
  final _abiertos = <ModuloCoordinacion>{ModuloCoordinacion.agenda};
  var _navegadores = _nuevosNavegadores();

  static Map<ModuloCoordinacion, GlobalKey<NavigatorState>> _nuevosNavegadores() =>
      {for (final m in ModuloCoordinacion.values) m: GlobalKey<NavigatorState>()};

  void _ir(int i) {
    final m = ModuloCoordinacion.values[i];
    if (m == _modulo) {
      // Tocar el módulo actual vuelve a su pantalla principal.
      _navegadores[m]!.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _modulo = m;
      _abiertos.add(m);
    });
  }

  void _cambiarArea(String? area) => setState(() {
        _area = area;
        _navegadores = _nuevosNavegadores();
        _abiertos
          ..clear()
          ..add(_modulo);
      });

  @override
  Widget build(BuildContext context) {
    return Cargador<ContextoCoordinacion>(
      cargar: Dependencias.de(context).coordinacion.contexto,
      construir: (context, ctx, _) {
        final area = ctx.areas.length == 1 ? ctx.areas.first.id : _area;
        final contenido = AmbienteCoordinacion(
          ctx: ctx,
          area: area,
          child: IndexedStack(
            index: _modulo.index,
            children: [
              for (final m in ModuloCoordinacion.values)
                if (_abiertos.contains(m))
                  Navigator(
                    key: _navegadores[m],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => m.paginaInicial),
                  )
                else
                  const SizedBox.shrink(),
            ],
          ),
        );
        final selectorArea = ctx.areas.length > 1
            ? DropdownButton<String?>(
                value: _area,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas mis áreas')),
                  for (final a in ctx.areas) DropdownMenuItem(value: a.id, child: Text(a.nombre)),
                ],
                onChanged: _cambiarArea,
              )
            : null;

        return LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= anchoEscritorio) {
              final extendido = c.maxWidth >= 1200;
              return Row(
                children: [
                  NavigationRail(
                    extended: extendido,
                    labelType: extendido ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                    selectedIndex: _modulo.index,
                    onDestinationSelected: _ir,
                    leading: selectorArea == null
                        ? null
                        : Padding(padding: const EdgeInsets.only(bottom: 8), child: extendido ? selectorArea : const Icon(Icons.layers_outlined)),
                    destinations: [
                      for (final m in ModuloCoordinacion.values)
                        NavigationRailDestination(icon: Icon(m.icono), selectedIcon: Icon(m.iconoActivo), label: Text(m.titulo)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        if (selectorArea != null && !extendido) _BarraArea(selector: selectorArea),
                        Expanded(child: contenido),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                if (selectorArea != null) _BarraArea(selector: selectorArea),
                Expanded(child: contenido),
                NavigationBarTheme(
                  // Letra pequeña para que "Profesionales" quepa en una línea.
                  data: const NavigationBarThemeData(labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                  child: NavigationBar(
                    selectedIndex: _modulo.index,
                    onDestinationSelected: _ir,
                    labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                    destinations: [
                      for (final m in ModuloCoordinacion.values)
                        NavigationDestination(icon: Icon(m.icono), selectedIcon: Icon(m.iconoActivo), label: m.titulo),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _BarraArea extends StatelessWidget {
  const _BarraArea({required this.selector});

  final Widget selector;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [const Text('Área: '), selector]),
    );
  }
}
