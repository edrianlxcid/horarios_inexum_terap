import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';

/// "NESC 3224 · Santiago Jaramillo · 8 años · Fase 1", como en la hoja de horarios.
String resumenParticipante(ParticipanteCita p) => [
      ?p.contrato,
      p.paciente,
      if (p.edadMeses != null) Formatos.edad(p.edadMeses),
      ?p.fase,
    ].join(' · ');

/// Un estudiante dentro de una cita: datos en una línea, su nota debajo y un
/// botón para editarla. Tocarlo abre su ficha.
class LineaParticipante extends StatelessWidget {
  const LineaParticipante({super.key, required this.participante, required this.alAbrir, required this.alCambiar});

  final ParticipanteCita participante;
  final VoidCallback alAbrir;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final p = participante;
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    return InkWell(
      onTap: alAbrir,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resumenParticipante(p), style: const TextStyle(fontSize: 13)),
                  if (p.observacion != null) Text('Nota: ${p.observacion}', style: gris.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            if (p.asistencia != 'PENDIENTE') Etiqueta(Formatos.etiqueta(p.asistencia), tono: tonoAsistencia(p.asistencia)),
            IconButton(
              tooltip: p.observacion == null ? 'Agregar nota' : 'Editar nota',
              visualDensity: VisualDensity.compact,
              icon: Icon(p.observacion == null ? Icons.note_add_outlined : Icons.edit_note, size: 20),
              onPressed: () async {
                if (await editarObservacion(context, p)) alCambiar();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Notas frecuentes en los horarios de Coordinación.
const notasFrecuentes = ['Solo por hoy', 'Desde esta semana', 'No mover', 'Rotativo', 'Reagendado'];

/// Edita la nota de coordinación de una cita. Devuelve true si se guardó.
Future<bool> editarObservacion(BuildContext context, ParticipanteCita p) async {
  final c = TextEditingController(text: p.observacion ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Nota de coordinación'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.paciente),
            const SizedBox(height: 12),
            TextField(controller: c, autofocus: true, maxLines: 2, decoration: const InputDecoration(labelText: 'Nota (vacía para quitarla)')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [for (final n in notasFrecuentes) ActionChip(label: Text(n), onPressed: () => c.text = n)],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Guardar')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return ejecutarConAviso(context, () => Dependencias.de(context).coordinacion.observacion(p.id, c.text.trim()), exito: 'Nota guardada');
}
