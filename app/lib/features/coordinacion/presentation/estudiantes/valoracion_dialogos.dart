import 'package:flutter/material.dart';

import '../../../recorrido/domain/recorrido.dart';
import '../../domain/modelos.dart';

/// Máximo de sesiones de una valoración (parámetro valoracion.sesiones_maximas).
const maximoSesionesValoracion = 20;

/// Sesiones previstas por especialidad de una valoración (de 1 a 20 en total).
/// [minimos]: lo que ya está agendado o hecho en cada especialidad (no se
/// puede prever menos). Devuelve {sub_area_id: sesiones} o null si se cancela.
Future<Map<String, int>?> mostrarPlanValoracion(
  BuildContext context,
  ContextoCoordinacion ctx, {
  required String tipo,
  Map<String, int> actual = const {},
  Map<String, int> minimos = const {},
}) {
  final plan = {...actual};
  final especialidades = ctx.especialidadesQueValoran(tipo);
  return showDialog<Map<String, int>>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) {
        final total = plan.values.fold(0, (s, n) => s + n);
        final valido = total >= 1 && total <= maximoSesionesValoracion;
        return AlertDialog(
          title: Text('${tipo == 'INICIAL' ? 'Valoración inicial' : 'Valoración final'}: sesiones previstas'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cuántas sesiones hará cada especialidad. Se pueden ampliar después.'),
                const SizedBox(height: 12),
                for (final e in especialidades)
                  Row(
                    children: [
                      Expanded(child: Text(e.nombre)),
                      IconButton(
                        tooltip: 'Una menos',
                        onPressed: (plan[e.id] ?? 0) <= (minimos[e.id] ?? 0)
                            ? null
                            : () => setState(() => (plan[e.id] ?? 0) <= 1 ? plan.remove(e.id) : plan[e.id] = plan[e.id]! - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(width: 28, child: Text('${plan[e.id] ?? 0}', textAlign: TextAlign.center)),
                      IconButton(
                        tooltip: 'Una más',
                        onPressed: total >= maximoSesionesValoracion ? null : () => setState(() => plan[e.id] = (plan[e.id] ?? 0) + 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                const Divider(),
                Text('Total: $total de $maximoSesionesValoracion como máximo',
                    style: TextStyle(color: valido ? null : Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            FilledButton(onPressed: valido ? () => Navigator.pop(d, plan) : null, child: const Text('Guardar')),
          ],
        );
      },
    ),
  );
}

/// Resultado de una valoración al cerrarla.
class CierreValoracion {
  const CierreValoracion(this.resultado, this.conclusion, this.programaRecomendadoId);

  final String resultado;
  final String? conclusion, programaRecomendadoId;
}

/// Pide el resultado, la conclusión y (en la inicial) el programa recomendado.
Future<CierreValoracion?> mostrarCerrarValoracion(BuildContext context, ContextoCoordinacion ctx, ValoracionProceso v) {
  final opciones = resultadosPorTipo[v.tipo]!;
  var resultado = opciones.first;
  String? programa;
  final conclusion = TextEditingController();
  return showDialog<CierreValoracion>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) => AlertDialog(
        title: Text('Cerrar ${v.titulo.toLowerCase()}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${v.realizadas} sesiones realizadas de ${v.previstas} previstas.'),
              const SizedBox(height: 12),
              const Text('Resultado'),
              Wrap(
                spacing: 6,
                children: [
                  for (final o in opciones)
                    ChoiceChip(label: Text(nombresResultados[o]!), selected: resultado == o, onSelected: (_) => setState(() => resultado = o)),
                ],
              ),
              if (v.tipo == 'INICIAL' && resultado == 'INGRESA_A_PROGRAMA') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: programa,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Programa recomendado'),
                  items: [for (final p in ctx.programasDeTerapia) DropdownMenuItem(value: p.id, child: Text(p.nombre))],
                  onChanged: (x) => setState(() => programa = x),
                ),
              ],
              const SizedBox(height: 12),
              TextField(controller: conclusion, maxLines: 3, decoration: const InputDecoration(labelText: 'Conclusión')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(
              d,
              CierreValoracion(resultado, conclusion.text.trim().isEmpty ? null : conclusion.text.trim(),
                  resultado == 'INGRESA_A_PROGRAMA' ? programa : null),
            ),
            child: const Text('Cerrar valoración'),
          ),
        ],
      ),
    ),
  );
}
