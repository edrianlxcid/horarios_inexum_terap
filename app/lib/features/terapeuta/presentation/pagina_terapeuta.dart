import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';
import 'ficha_paciente.dart';
import 'nota_dialogo.dart';

/// Agenda del día del terapeuta: asistencia en un toque y notas de sesión.
class PaginaTerapeuta extends StatefulWidget {
  const PaginaTerapeuta({super.key});

  @override
  State<PaginaTerapeuta> createState() => _PaginaTerapeutaState();
}

class _PaginaTerapeutaState extends State<PaginaTerapeuta> {
  DateTime _dia = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).terapeuta;
    return Cargador<AgendaTerapeuta>(
      key: ValueKey(Formatos.fechaIso(_dia)),
      cargar: () => api.agenda(_dia, _dia),
      construir: (context, agenda, recargar) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(agenda.terapeuta, style: Theme.of(context).textTheme.titleLarge),
          Text(agenda.profesion, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          SelectorDia(dia: _dia, texto: Formatos.fechaLarga(_dia), alCambiar: (d) => setState(() => _dia = d)),
          if (agenda.sesiones.isEmpty)
            const Aviso(icono: Icons.event_available, texto: 'No tienes sesiones este día.')
          else
            for (final s in agenda.sesiones) _TarjetaSesion(sesion: s, alCambiar: recargar),
        ],
      ),
    );
  }
}

class _TarjetaSesion extends StatelessWidget {
  const _TarjetaSesion({required this.sesion, required this.alCambiar});

  final SesionTerapeuta sesion;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final s = sesion;
    final cancelada = s.estado == 'CANCELADA';
    final lugar = [s.sede, ?s.sala].join(' · ');
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${Formatos.hora(s.inicio)} – ${Formatos.hora(s.fin)}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(child: Text([s.programa ?? Formatos.etiqueta(s.tipo), if (s.grupo != null) 'Grupo ${s.grupo}'].join(' · '))),
                Etiqueta(Formatos.etiqueta(s.estado), tono: cancelada ? Tono.mal : Tono.neutro),
              ],
            ),
            Text(lugar, style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            for (final p in s.participantes)
              _FilaParticipante(participante: p, editable: !cancelada, alCambiar: alCambiar),
            if (s.participantes.isEmpty) const Text('Sin pacientes en esta sesión.'),
          ],
        ),
      ),
    );
  }
}

class _FilaParticipante extends StatelessWidget {
  const _FilaParticipante({required this.participante, required this.editable, required this.alCambiar});

  final ParticipanteSesion participante;
  final bool editable;
  final VoidCallback alCambiar;

  static const _opciones = {
    'PENDIENTE': 'Pendiente',
    'ASISTIO': 'Asistió',
    'FALTA': 'Faltó',
    'FALTA_JUSTIFICADA': 'Falta justificada',
  };

  @override
  Widget build(BuildContext context) {
    final p = participante;
    final api = Dependencias.de(context).terapeuta;
    final detalle = [
      Formatos.edad(p.edadMeses),
      if (p.valoracion != null) 'Valoración ${p.valoracion == 'FINAL' ? 'final' : 'inicial'}${p.especialidad != null ? ' · ${p.especialidad}' : ''}',
      if (p.numeroSesion != null) 'sesión ${p.numeroSesion}${p.totalSesiones != null ? ' de ${p.totalSesiones}' : ''}',
      ?p.fase,
      if (p.demanda != null) 'demanda ${p.demanda!.toLowerCase()}',
    ].join(' · ');
    final colores = Theme.of(context).colorScheme;
    final colorNota = switch (p.nota) {
      'FIRMADA' => colores.primary,
      'BORRADOR' => colores.tertiary,
      _ => Theme.of(context).disabledColor,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 280,
            child: InkWell(
              onTap: () => mostrarFichaPaciente(context, p.pacienteId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.paciente, style: const TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                  Text(detalle, style: Theme.of(context).textTheme.bodySmall),
                  if (p.trabajado != null) Text('Trabajado: ${p.trabajado}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          if (_opciones.containsKey(p.asistencia))
            DropdownButton<String>(
              value: p.asistencia,
              items: [for (final e in _opciones.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: !editable
                  ? null
                  : (v) async {
                      if (v == null || v == p.asistencia) return;
                      final ok = await ejecutarConAviso(context, () => api.marcarAsistencia(p.participanteId, v),
                          exito: 'Asistencia registrada');
                      if (ok) alCambiar();
                    },
            )
          else
            Etiqueta(Formatos.etiqueta(p.asistencia), tono: tonoAsistencia(p.asistencia)),
          IconButton(
            tooltip: p.asistencia == 'ASISTIO' ? 'Nota de sesión (${Formatos.etiqueta(p.nota)})' : 'La nota se habilita al marcar "Asistió"',
            icon: Icon(Icons.edit_note, color: colorNota),
            onPressed: p.asistencia != 'ASISTIO'
                ? null
                : () async {
                    final cambio = await mostrarNotaDialogo(context, p.participanteId);
                    if (cambio == true) alCambiar();
                  },
          ),
        ],
      ),
    );
  }
}
