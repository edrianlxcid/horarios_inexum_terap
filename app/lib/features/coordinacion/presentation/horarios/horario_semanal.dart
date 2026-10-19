import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../agenda/agendar_dialogo.dart';
import '../agenda/participante_cita.dart';
import '../coordinacion_comun.dart';

/// Lunes de la semana de [dia].
DateTime lunesDe(DateTime dia) => DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1));

/// "Semana del 12 al 17 oct" con flechas y botón "Esta semana".
class SelectorSemana extends StatelessWidget {
  const SelectorSemana({super.key, required this.semana, required this.alCambiar});

  final DateTime semana;
  final ValueChanged<DateTime> alCambiar;

  @override
  Widget build(BuildContext context) {
    final lunes = lunesDe(semana);
    final sabado = lunes.add(const Duration(days: 5));
    String mes(DateTime d) => DateFormat.MMM('es').format(d);
    final texto = lunes.month == sabado.month
        ? '${lunes.day} al ${sabado.day} ${mes(sabado)}'
        : '${lunes.day} ${mes(lunes)} al ${sabado.day} ${mes(sabado)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Semana anterior', onPressed: () => alCambiar(lunes.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left)),
        Text('Semana del $texto'),
        IconButton(tooltip: 'Semana siguiente', onPressed: () => alCambiar(lunes.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: () => alCambiar(DateTime.now()), child: const Text('Esta semana')),
      ],
    );
  }
}

/// Colores de cada tipo de celda (fondo, texto).
(Color, Color) coloresCelda(BuildContext context, TipoCelda tipo, {Color? profesional}) {
  final c = Theme.of(context).colorScheme;
  return switch (tipo) {
    TipoCelda.fuera => (c.surfaceContainerLow, c.outline),
    TipoCelda.libre => (c.surface, c.primary),
    TipoCelda.pausa => (c.surfaceContainerHighest, c.onSurfaceVariant),
    TipoCelda.ausencia => (c.errorContainer, c.onErrorContainer),
    TipoCelda.feriado => (c.tertiaryContainer, c.onTertiaryContainer),
    TipoCelda.sesion => ((profesional ?? c.primary).withValues(alpha: 0.16), c.onSurface),
  };
}

class LeyendaHorario extends StatelessWidget {
  const LeyendaHorario({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(TipoCelda t, String texto) {
      final (fondo, _) = coloresCelda(context, t);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: fondo, border: Border.all(color: Theme.of(context).colorScheme.outlineVariant))),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ]);
    }

    return Wrap(spacing: 14, runSpacing: 4, children: [
      item(TipoCelda.libre, 'Libre (toca para agendar)'),
      item(TipoCelda.sesion, 'Sesión'),
      item(TipoCelda.pausa, 'Pausa'),
      item(TipoCelda.ausencia, 'Ausencia'),
      item(TipoCelda.feriado, 'Feriado'),
    ]);
  }
}

/// Semana de un profesional en columnas de lunes a sábado, cada una con sus
/// turnos y pausas, como la hoja de horarios de Coordinación. En Neuro los
/// turnos son de una hora; en Terapia de lenguaje, de 45 minutos seguidos.
class GrillaSemanal extends StatelessWidget {
  const GrillaSemanal({super.key, required this.semana, required this.profesional, this.alAgendar, this.alCambiar});

  final SemanaHorario semana;
  final ProfesionalSemana profesional;

  /// Se llama al tocar un turno libre, con el día y la hora de inicio ("09:45").
  final void Function(DateTime dia, String hora)? alAgendar;

  /// Se llama cuando cambia algo de una cita (por ejemplo, su nota).
  final VoidCallback? alCambiar;

  @override
  Widget build(BuildContext context) {
    final hoy = Formatos.fechaIso(DateTime.now());
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(c.maxWidth, 6 * 150.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final d in semana.dias)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              Text(DateFormat('EEEE d', 'es').format(d),
                                  style: TextStyle(fontWeight: Formatos.fechaIso(d) == hoy ? FontWeight.w800 : FontWeight.w600)),
                              Text('${Formatos.numero(profesional.horasDel(d.weekday))} h · '
                                  '${profesional.sesionesDel(d).length} ses.', style: gris),
                            ],
                          ),
                        ),
                        for (final f in profesional.franjasDel(d, semana.feriados))
                          _CeldaHorario(
                            franja: f,
                            color: profesional.color,
                            alCambiar: alCambiar,
                            alTocarLibre: alAgendar == null ? null : () => alAgendar!(d, hhmm(f.inicio)),
                          ),
                        if (profesional.jornadasDel(d.weekday).isEmpty)
                          Padding(padding: const EdgeInsets.all(8), child: Text('No trabaja', textAlign: TextAlign.center, style: gris)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CeldaHorario extends StatelessWidget {
  const _CeldaHorario({required this.franja, required this.color, this.alTocarLibre, this.alCambiar});

  final FranjaHorario franja;
  final Color color;
  final VoidCallback? alTocarLibre;
  final VoidCallback? alCambiar;

  @override
  Widget build(BuildContext context) {
    final celda = franja.celda;
    final (fondo, frente) = coloresCelda(context, celda.tipo, profesional: color);
    final s = celda.sesion;
    final pausa = celda.tipo == TipoCelda.pausa;
    final hora = Text(franja.hora, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor));
    final contenido = switch (celda.tipo) {
      TipoCelda.libre => Text('Libre', style: TextStyle(fontSize: 12, color: frente)),
      TipoCelda.sesion => Text(
          '${s!.titulo} · ${s.participantes.length}/${s.cupo}${s.grupo != null ? ' · ${s.grupo}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      _ => Text(celda.texto ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: frente)),
    };
    final caja = Container(
      margin: const EdgeInsets.only(bottom: 2),
      height: pausa ? 34 : 58,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(4),
        border: celda.tipo == TipoCelda.sesion
            ? Border(left: BorderSide(color: color, width: 3))
            : Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: pausa
          ? Row(children: [hora, const SizedBox(width: 6), Expanded(child: contenido)])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [hora, const SizedBox(height: 2), Expanded(child: contenido)]),
    );
    return switch (celda.tipo) {
      TipoCelda.libre when alTocarLibre != null => InkWell(onTap: alTocarLibre, child: caja),
      TipoCelda.sesion => InkWell(onTap: () => _verSesion(context, s!), child: caja),
      _ => caja,
    };
  }

  /// Detalle de la cita: cada estudiante con contrato, edad, fase y nota.
  /// Tocar un estudiante cierra el detalle y abre su ficha.
  Future<void> _verSesion(BuildContext context, SesionHorario s) async {
    var cambio = false;
    final abrir = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.titulo),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${Formatos.fechaCorta(s.fecha)} · ${s.inicio}–${s.fin} · ${s.sede}'),
              Text('${Formatos.etiqueta(s.tipo)}${s.grupo != null ? ' · grupo ${s.grupo}' : ''} · ${s.participantes.length} de ${s.cupo}'),
              const SizedBox(height: 12),
              for (final p in s.participantes)
                LineaParticipante(
                  participante: p,
                  alAbrir: () => Navigator.pop(d, p.pacienteId),
                  alCambiar: () {
                    cambio = true;
                    Navigator.pop(d);
                  },
                ),
              if (s.participantes.isEmpty) const Text('Sin estudiantes.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cerrar'))],
      ),
    );
    if (cambio) alCambiar?.call();
    if (abrir != null && context.mounted) await abrirEstudiante(context, abrir);
  }
}

/// Horario semanal de un profesional con su selector de semana. Al tocar un
/// turno libre abre "Agendar" con el profesional, el día y la hora puestos.
class HorarioDeProfesional extends StatefulWidget {
  const HorarioDeProfesional({super.key, required this.profesionalId, this.semanaInicial});

  final String profesionalId;
  final DateTime? semanaInicial;

  @override
  State<HorarioDeProfesional> createState() => _HorarioDeProfesionalState();
}

class _HorarioDeProfesionalState extends State<HorarioDeProfesional> {
  late DateTime _semana = widget.semanaInicial ?? DateTime.now();
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectorSemana(semana: _semana, alCambiar: (d) => setState(() => _semana = d)),
        const LeyendaHorario(),
        const SizedBox(height: 8),
        Cargador<SemanaHorario>(
          key: ValueKey('${Formatos.fechaIso(lunesDe(_semana))}$_version'),
          cargar: () => api.horarios(_semana, profesional: widget.profesionalId),
          construir: (context, semana, _) {
            final p = semana.profesionales.firstOrNull;
            if (p == null) return const Aviso(icono: Icons.event_busy, texto: 'Sin horario en esta semana.');
            return GrillaSemanal(
              semana: semana,
              profesional: p,
              alAgendar: (dia, hora) async {
                final ok = await mostrarAgendar(context, ctx: amb.ctx, area: amb.area, dia: dia, profesionalId: p.id, hora: hora);
                if (ok == true) setState(() => _version++);
              },
              alCambiar: () => setState(() => _version++),
            );
          },
        ),
      ],
    );
  }
}
