import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';

/// Panel de Gerencia: indicadores del día con su detalle y evolución, y bonos.
class PaginaGerencia extends StatelessWidget {
  const PaginaGerencia({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Indicadores'), Tab(text: 'Bonos de desempeño')]),
          Expanded(child: TabBarView(children: [_Indicadores(), _Bonos()])),
        ],
      ),
    );
  }
}

class _Indicadores extends StatefulWidget {
  const _Indicadores();

  @override
  State<_Indicadores> createState() => _IndicadoresState();
}

class _IndicadoresState extends State<_Indicadores> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).gerencia;
    return Cargador<PanelGerencia>(
      key: ValueKey(_version),
      cargar: api.panel,
      construir: (context, panel, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('Datos al ${Formatos.fechaCorta(panel.fecha)}. Toca un indicador para ver el detalle y cómo se calcula.')),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await ejecutarConAviso(context, api.recalcular, exito: 'Indicadores recalculados');
                  if (ok) setState(() => _version++);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Recalcular hoy'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final i in panel.indicadores) _TarjetaIndicador(indicador: i, panel: panel),
        ],
      ),
    );
  }
}

class _TarjetaIndicador extends StatelessWidget {
  const _TarjetaIndicador({required this.indicador, required this.panel});

  final Indicador indicador;
  final PanelGerencia panel;

  String _valor(double? v) => switch (indicador.unidad) {
        _ when v == null => '—',
        'PORCENTAJE' => '${Formatos.numero(v, decimales: 1)} %',
        'PUNTAJE' => '${Formatos.numero(v, decimales: 2)} / 5',
        'DOLARES' => Formatos.dinero(v),
        _ => Formatos.numero(v),
      };

  @override
  Widget build(BuildContext context) {
    final i = indicador;
    final valores = panel.valoresDe(i.codigo);
    final serie = panel.series[i.codigo];
    final metas = panel.metas.where((m) => m['codigo'] == i.codigo).toList();
    final porSede = i.dimension == 'SEDE' || i.dimension == 'SEDE_AREA';
    return Card(
      child: ExpansionTile(
        title: Text(i.nombre),
        subtitle: Text(porSede ? 'Total de la empresa' : '${valores.length} registros · ${i.descripcion}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (serie != null && serie.length > 1) SizedBox(width: 90, height: 28, child: CustomPaint(painter: _Linea(serie, Theme.of(context).colorScheme.primary))),
            const SizedBox(width: 12),
            Text(porSede ? _valor(panel.total(i)) : (valores.isEmpty ? '—' : ''), style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cómo se calcula: ${i.formula}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (valores.isEmpty) const Text('Sin datos para este día.'),
          for (final v in valores.take(12))
            Row(
              children: [
                Expanded(child: Text(v.etiqueta.isEmpty ? 'General' : v.etiqueta)),
                Text(_valor(v.valor)),
              ],
            ),
          if (valores.length > 12) Text('… y ${valores.length - 12} más'),
          for (final m in metas) Text('Meta ${m['sede'] ?? ''}: ${_valor((m['meta'] as num).toDouble())}', style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// Evolución de los últimos 30 días en una línea simple.
class _Linea extends CustomPainter {
  _Linea(this.valores, this.color);

  final List<double> valores;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final minimo = valores.reduce((a, b) => a < b ? a : b);
    final maximo = valores.reduce((a, b) => a > b ? a : b);
    final rango = maximo - minimo == 0 ? 1 : maximo - minimo;
    final camino = Path();
    for (var i = 0; i < valores.length; i++) {
      final x = size.width * i / (valores.length - 1);
      final y = size.height - (valores[i] - minimo) / rango * size.height;
      i == 0 ? camino.moveTo(x, y) : camino.lineTo(x, y);
    }
    canvas.drawPath(camino, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_Linea old) => old.valores != valores;
}

class _Bonos extends StatefulWidget {
  const _Bonos();

  @override
  State<_Bonos> createState() => _BonosState();
}

class _BonosState extends State<_Bonos> {
  String? _periodo;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).gerencia;
    return Cargador<Map<String, dynamic>>(
      key: ValueKey(_periodo),
      cargar: () => api.bonos(periodo: _periodo),
      construir: (context, r, _) {
        final bonos = (r['bonos'] as List).cast<Map<String, dynamic>>();
        final periodos = (r['periodos'] as List).cast<String>();
        final total = bonos.fold<double>(0, (a, b) => a + (b['monto'] as num));
        final posible = bonos.fold<double>(0, (a, b) => a + (b['monto_posible'] as num));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Text('Periodo: '),
                DropdownButton<String>(
                  value: r['periodo'] as String,
                  items: [for (final p in periodos) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) => setState(() => _periodo = v),
                ),
                const Spacer(),
                Text('Total: ${Formatos.dinero(total)} de ${Formatos.dinero(posible)} posibles'),
              ],
            ),
            const Text('El bono depende del promedio con el que las familias evalúan a cada terapeuta.'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Terapeuta')),
                  DataColumn(label: Text('Evaluaciones'), numeric: true),
                  DataColumn(label: Text('Promedio'), numeric: true),
                  DataColumn(label: Text('% del bono'), numeric: true),
                  DataColumn(label: Text('Ganó'), numeric: true),
                  DataColumn(label: Text('Pudo ganar'), numeric: true),
                ],
                rows: [
                  for (final b in bonos)
                    DataRow(cells: [
                      DataCell(Text('${b['terapeuta']}\n${b['profesion']}')),
                      DataCell(Text('${b['evaluaciones']}')),
                      DataCell(Text(Formatos.numero(b['promedio'] as num?, decimales: 2))),
                      DataCell(Text('${Formatos.numero(b['porcentaje'] as num?)} %')),
                      DataCell(Text(Formatos.dinero(b['monto'] as num?))),
                      DataCell(Text(Formatos.dinero(b['monto_posible'] as num?))),
                    ]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
