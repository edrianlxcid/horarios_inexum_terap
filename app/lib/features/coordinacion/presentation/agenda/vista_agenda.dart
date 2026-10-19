import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../coordinacion_comun.dart';
import 'agendar_dialogo.dart';

/// Sesiones de un día, con filtro por terapeuta. Desde cada sesión se abre
/// la ficha del profesional o de sus estudiantes, o se cancela.
class VistaAgenda extends StatefulWidget {
  const VistaAgenda({super.key});

  @override
  State<VistaAgenda> createState() => _VistaAgendaState();
}

class _VistaAgendaState extends State<VistaAgenda> {
  DateTime _dia = DateTime.now();
  String? _terapeuta;
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    return Column(
      children: [
        EncabezadoPagina(
          titulo: 'Agenda del día',
          subtitulo: Formatos.fechaLarga(_dia),
          acciones: [
            FilledButton.icon(
              onPressed: () async {
                final ok = await mostrarAgendar(context, ctx: amb.ctx, area: amb.area, dia: _dia);
                if (ok == true) setState(() => _version++);
              },
              icon: const Icon(Icons.add),
              label: const Text('Agendar'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              SelectorDia(dia: _dia, texto: Formatos.fechaCorta(Formatos.fechaIso(_dia)), alCambiar: (d) => setState(() => _dia = d)),
              FiltroLista<String>(
                todos: 'Todos los terapeutas',
                valor: _terapeuta,
                opciones: [for (final t in amb.ctx.terapeutasDeArea(amb.area)) (t.id, t.nombre)],
                alCambiar: (v) => setState(() => _terapeuta = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: Cargador<List<SesionCoordinacion>>(
            key: ValueKey('${Formatos.fechaIso(_dia)}$_terapeuta$_version'),
            cargar: () => api.agenda(_dia, area: amb.area, profesional: _terapeuta),
            construir: (context, sesiones, recargar) {
              if (sesiones.isEmpty) return const Aviso(icono: Icons.event_busy, texto: 'No hay sesiones este día.');
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('${sesiones.length} sesiones · '
                        '${sesiones.fold<int>(0, (s, x) => s + x.participantes.length)} estudiantes'),
                  ),
                  for (final s in sesiones) _TarjetaSesion(sesion: s, alCambiar: recargar),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TarjetaSesion extends StatelessWidget {
  const _TarjetaSesion({required this.sesion, required this.alCambiar});

  final SesionCoordinacion sesion;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final s = sesion;
    final nombres = s.participantes.map((p) => p['paciente']).join(', ');
    return Card(
      child: ListTile(
        leading: Text(Formatos.hora(s.inicio), style: Theme.of(context).textTheme.titleMedium),
        title: Text('${s.programa ?? Formatos.etiqueta(s.tipo)}${s.grupo != null ? ' · ${s.grupo}' : ''}'),
        subtitle: Text('${s.terapeuta} · ${s.sede} · ${s.participantes.length}/${s.cupo}'
            '${nombres.isEmpty ? '' : '\n$nombres'}'),
        isThreeLine: nombres.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.estado != 'PROGRAMADA')
              Etiqueta(Formatos.etiqueta(s.estado), tono: s.estado == 'CANCELADA' ? Tono.mal : Tono.neutro),
            PopupMenuButton<VoidCallback>(
              tooltip: 'Opciones',
              onSelected: (accion) => accion(),
              itemBuilder: (_) => [
                PopupMenuItem(value: () => abrirProfesional(context, s.profesionalId), child: Text('Ver a ${s.terapeuta}')),
                for (final p in s.participantes)
                  PopupMenuItem(value: () => abrirEstudiante(context, p['paciente_id'] as String), child: Text('Ver a ${p['paciente']}')),
                if (s.estado == 'PROGRAMADA')
                  PopupMenuItem(value: () => _cancelar(context), child: const Text('Cancelar sesión')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelar(BuildContext context) async {
    final motivo = await pedirMotivo(context);
    if (motivo == null || !context.mounted) return;
    final api = Dependencias.de(context).coordinacion;
    if (await ejecutarConAviso(context, () => api.cancelarSesion(sesion.id, motivo), exito: 'Sesión cancelada')) alCambiar();
  }
}

Future<String?> pedirMotivo(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Cancelar sesión'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Motivo')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cancelar sesión')),
      ],
    ),
  );
  return ok == true && c.text.trim().isNotEmpty ? c.text.trim() : null;
}
