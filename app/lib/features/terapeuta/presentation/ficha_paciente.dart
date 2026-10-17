import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';

/// Ficha del paciente para el terapeuta: datos, programas, objetivos, notas y tareas.
Future<void> mostrarFichaPaciente(BuildContext context, String pacienteId) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: _Ficha(pacienteId: pacienteId),
      ),
    ),
  );
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.pacienteId});

  final String pacienteId;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).terapeuta;
    return Cargador<Map<String, dynamic>>(
      cargar: () => api.paciente(pacienteId),
      construir: (context, p, recargar) {
        List<Map<String, dynamic>> lista(String k) => (p[k] as List).cast<Map<String, dynamic>>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text('${p['nombres']} ${p['apellidos']}'),
              subtitle: Text([p['codigo_historia'], Formatos.edad(p['edad_meses'] as int?), p['sede'],
                if (p['demanda'] != null) 'demanda ${p['demanda']}'].join(' · ')),
              trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  const TituloSeccion('Representantes'),
                  for (final r in lista('representantes'))
                    Text('${r['nombre']} (${Formatos.etiqueta(r['parentesco'] as String?)}) · ${r['telefono'] ?? 'sin teléfono'}'),
                  const TituloSeccion('Programas'),
                  for (final m in lista('matriculas'))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m['programa'] as String),
                      subtitle: LinearProgressIndicator(value: (m['sesiones_consumidas'] as int) / (m['sesiones_contratadas'] as int)),
                      trailing: Text('${m['sesiones_consumidas']}/${m['sesiones_contratadas']} · ${Formatos.etiqueta(m['estado'] as String?)}'),
                    ),
                  const TituloSeccion('Objetivos'),
                  for (final o in lista('objetivos'))
                    Text('• ${o['descripcion']} — ${Formatos.etiqueta(o['estado'] as String?)}'
                        '${o['ultimo_nivel'] != null ? ' (nivel ${o['ultimo_nivel']}/5)' : ''}'),
                  TituloSeccion(
                    'Tareas para casa',
                    accion: TextButton.icon(
                      onPressed: () async {
                        if (await _asignarTarea(context, pacienteId)) recargar();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Asignar'),
                    ),
                  ),
                  for (final t in lista('tareas'))
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: t['completada'] as bool,
                      onChanged: null,
                      title: Text(t['titulo'] as String),
                      subtitle: Text([t['descripcion'] ?? '', if (t['comentario_familia'] != null) 'Familia: ${t['comentario_familia']}'].join('\n')),
                    ),
                  const TituloSeccion('Últimas notas'),
                  for (final n in lista('notas'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${Formatos.fechaCorta(n['fecha'] as String?)} · ${n['programa'] ?? ''} · ${n['terapeuta']}'
                              '${n['firmada'] == true ? '' : ' · borrador'}',
                              style: Theme.of(context).textTheme.labelMedium),
                          Text(n['contenido'] as String? ?? ''),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<bool> _asignarTarea(BuildContext context, String pacienteId) async {
  final titulo = TextEditingController();
  final descripcion = TextEditingController();
  DateTime? limite;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Nueva tarea para casa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titulo, decoration: const InputDecoration(labelText: 'Título')),
            const SizedBox(height: 8),
            TextField(controller: descripcion, maxLines: 3, decoration: const InputDecoration(labelText: 'Indicaciones')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(limite == null ? 'Fecha límite (opcional)' : Formatos.fechaCorta(Formatos.fechaIso(limite!))),
              onPressed: () async {
                final d = await showDatePicker(
                    context: c, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime(2030));
                if (d != null) setState(() => limite = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Asignar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  return ejecutarConAviso(
    context,
    () => Dependencias.de(context).terapeuta.asignarTarea(
          pacienteId,
          titulo: titulo.text.trim(),
          descripcion: descripcion.text.trim(),
          fechaLimite: limite == null ? null : Formatos.fechaIso(limite!),
        ),
    exito: 'Tarea asignada',
  );
}
