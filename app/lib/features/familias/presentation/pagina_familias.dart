import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';

/// Portal de familias: próximas sesiones, progreso, tareas y contrato vigente.
/// Si hay una evaluación pendiente, el progreso se muestra después de evaluar.
class PaginaFamilias extends StatefulWidget {
  const PaginaFamilias({super.key});

  @override
  State<PaginaFamilias> createState() => _PaginaFamiliasState();
}

class _PaginaFamiliasState extends State<PaginaFamilias> {
  String? _hijoId;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).familias;
    return Cargador<List<Hijo>>(
      cargar: api.hijos,
      construir: (context, hijos, _) {
        if (hijos.isEmpty) return const Aviso(icono: Icons.family_restroom, texto: 'No hay pacientes asociados a tu cuenta.');
        final actual = hijos.firstWhere((h) => h.id == _hijoId, orElse: () => hijos.first);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final h in hijos)
                  ChoiceChip(
                    label: Text('${h.nombres.split(' ').first} · ${Formatos.edad(h.edadMeses)}'),
                    selected: h.id == actual.id,
                    onSelected: (_) => setState(() => _hijoId = h.id),
                  ),
              ],
            ),
            Cargador<ResumenHijo>(
              key: ValueKey(actual.id),
              cargar: () => api.resumen(actual.id),
              construir: (context, r, recargar) => _Resumen(hijo: actual, resumen: r, recargar: recargar),
            ),
          ],
        );
      },
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.hijo, required this.resumen, required this.recargar});

  final Hijo hijo;
  final ResumenHijo resumen;
  final VoidCallback recargar;

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final api = Dependencias.de(context).familias;
    final bloqueado = r.evaluacionesPendientes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in r.evaluacionesPendientes)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text('Evalúa a ${e.terapeuta}'),
              subtitle: Text('${e.programa}. Antes de ver los resultados, cuéntanos cómo fue la atención.'),
              trailing: FilledButton(
                onPressed: () async {
                  if (await _evaluar(context, e)) recargar();
                },
                child: const Text('Evaluar'),
              ),
            ),
          ),
        const TituloSeccion('Próximas sesiones'),
        if (r.proximas.isEmpty) const Text('No hay sesiones agendadas.'),
        for (final s in r.proximas)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('${Formatos.fechaHora(s.inicio)} · ${s.programa ?? Formatos.etiqueta(s.tipo)}'),
            subtitle: Text('${s.terapeuta} · ${s.sede}${s.numeroSesion != null ? ' · sesión ${s.numeroSesion}' : ''}'),
            trailing: s.solicitudPendiente
                ? const Etiqueta('Cambio solicitado', tono: Tono.alerta)
                : TextButton(
                    onPressed: () async {
                      if (await _pedirCambio(context, s)) recargar();
                    },
                    child: const Text('Pedir cambio'),
                  ),
          ),
        const TituloSeccion('Programas'),
        for (final p in r.programas)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${p.programa}${p.fase != null ? ' · ${p.fase}' : ''}'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: p.contratadas == 0 ? 0 : p.realizadas / p.contratadas),
            ),
            trailing: Text('Sesión ${p.realizadas} de ${p.contratadas}\n${Formatos.etiqueta(p.estado)}', textAlign: TextAlign.end),
          ),
        if (!bloqueado) ...[
          const TituloSeccion('Objetivos'),
          for (final o in r.objetivos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(o['estado'] == 'LOGRADO' ? Icons.check_circle : Icons.flag_outlined),
              title: Text(o['descripcion'] as String),
              subtitle: Text('${o['programa']} · ${Formatos.etiqueta(o['estado'] as String?)}'
                  '${o['ultimo_nivel'] != null ? ' · avance ${o['ultimo_nivel']} de 5' : ''}'),
            ),
          const TituloSeccion('Últimas sesiones'),
          for (final h in r.historial)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${Formatos.fechaCorta(h['fecha'] as String?)} · ${h['programa'] ?? ''} · ${h['terapeuta']}'),
              subtitle: Text(h['resumen'] as String? ?? 'Sin resumen.'),
              trailing: Etiqueta(Formatos.etiqueta(h['asistencia'] as String?), tono: tonoAsistencia(h['asistencia'] as String?)),
            ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Los objetivos y el resumen de las sesiones se muestran después de evaluar al terapeuta.'),
          ),
        const TituloSeccion('Tareas para casa'),
        if (r.tareas.isEmpty) const Text('No hay tareas asignadas.'),
        for (final t in r.tareas)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: t.completada,
            title: Text(t.titulo),
            subtitle: Text([t.descripcion ?? '', 'Asignada por ${t.terapeuta}',
              if (t.fechaLimite != null) 'hasta ${Formatos.fechaCorta(t.fechaLimite)}'].where((x) => x.isNotEmpty).join(' · ')),
            onChanged: t.completada
                ? null
                : (_) async {
                    if (await ejecutarConAviso(context, () => api.completarTarea(t.id), exito: '¡Tarea completada!')) recargar();
                  },
          ),
        const TituloSeccion('Contrato'),
        if (r.contratos.isEmpty) const Text('No hay contrato vigente.'),
        for (final c in r.contratos)
          Text('${c['codigo']} · vigente hasta ${Formatos.fechaCorta(c['vigente_hasta'] as String?)} · ${Formatos.etiqueta(c['estado'] as String?)}'),
      ],
    );
  }
}

Future<bool> _evaluar(BuildContext context, EvaluacionPendiente e) async {
  final api = Dependencias.de(context).familias;
  final escala = await api.escala();
  if (!context.mounted) return false;
  int? puntaje;
  final comentario = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('¿Cómo fue la atención de ${e.terapeuta}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (valor, etiqueta) in escala)
                  ChoiceChip(label: Text('$valor · $etiqueta'), selected: puntaje == valor, onSelected: (_) => setState(() => puntaje = valor)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: comentario, maxLines: 3, decoration: const InputDecoration(labelText: 'Comentario (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Después')),
          FilledButton(onPressed: puntaje == null ? null : () => Navigator.pop(c, true), child: const Text('Enviar')),
        ],
      ),
    ),
  );
  if (ok != true || puntaje == null || !context.mounted) return false;
  return ejecutarConAviso(
    context,
    () => api.evaluar(e, puntaje: puntaje!, comentario: comentario.text.trim().isEmpty ? null : comentario.text.trim()),
    exito: 'Gracias por tu evaluación',
  );
}

Future<bool> _pedirCambio(BuildContext context, ProximaSesion s) async {
  var tipo = 'REPROGRAMAR';
  final motivo = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('Cambio de la sesión del ${Formatos.fechaHora(s.inicio)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'REPROGRAMAR', label: Text('Reprogramar')),
                ButtonSegment(value: 'CANCELAR', label: Text('Cancelar')),
              ],
              selected: {tipo},
              onSelectionChanged: (v) => setState(() => tipo = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: motivo, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cerrar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enviar solicitud')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  return ejecutarConAviso(
    context,
    () => Dependencias.de(context).familias.solicitarCambio(s.participanteId, tipo: tipo, motivo: motivo.text.trim()),
    exito: 'Solicitud enviada. Coordinación te confirmará.',
  );
}
