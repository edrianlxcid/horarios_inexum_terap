import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../agenda/agendar_dialogo.dart';
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
      item(TipoCelda.fuera, 'Fuera de horario'),
    ]);
  }
}

/// Grilla hora × día (lunes a sábado) de un profesional.
class GrillaSemanal extends StatelessWidget {
  const GrillaSemanal({super.key, required this.semana, required this.profesional, this.alAgendar});

  final SemanaHorario semana;
  final ProfesionalSemana profesional;

  /// Se llama al tocar una hora libre con el día y la hora ("09:00").
  final void Function(DateTime dia, String hora)? alAgendar;

  @override
  Widget build(BuildContext context) {
    final (desde, hasta) = semana.rangoHoras([profesional]);
    final borde = Theme.of(context).colorScheme.outlineVariant;
    final hoy = Formatos.fechaIso(DateTime.now());
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: c.maxWidth < 760 ? 760 : c.maxWidth,
          child: Table(
            border: TableBorder.all(color: borde),
            columnWidths: const {0: FixedColumnWidth(56)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox(height: 40),
                  for (final d in semana.dias)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        children: [
                          Text(DateFormat('EEE d', 'es').format(d),
                              style: TextStyle(fontWeight: Formatos.fechaIso(d) == hoy ? FontWeight.w800 : FontWeight.w600)),
                          Text('${Formatos.numero(profesional.horasDel(d.weekday), decimales: 0)} h · '
                              '${profesional.sesionesDel(d).length} ses.', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
              for (var h = desde; h < hasta; h++)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text('${h.toString().padLeft(2, '0')}:00', style: const TextStyle(fontSize: 12)),
                    ),
                    for (final d in semana.dias) _CeldaHorario(
                      celda: profesional.celda(d, h, semana.feriados),
                      color: profesional.color,
                      alTocarLibre: alAgendar == null ? null : () => alAgendar!(d, '${h.toString().padLeft(2, '0')}:00'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CeldaHorario extends StatelessWidget {
  const _CeldaHorario({required this.celda, required this.color, this.alTocarLibre});

  final Celda celda;
  final Color color;
  final VoidCallback? alTocarLibre;

  @override
  Widget build(BuildContext context) {
    final (fondo, frente) = coloresCelda(context, celda.tipo, profesional: color);
    final s = celda.sesion;
    final contenido = switch (celda.tipo) {
      TipoCelda.fuera => const SizedBox.shrink(),
      TipoCelda.libre => Text('Libre', style: TextStyle(fontSize: 11, color: frente)),
      TipoCelda.sesion => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s!.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${s.inicio} · ${s.participantes.length}/${s.cupo}${s.grupo != null ? ' · ${s.grupo}' : ''}',
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      _ => Text(celda.texto ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: frente)),
    };
    final caja = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: fondo,
        border: celda.tipo == TipoCelda.sesion ? Border(left: BorderSide(color: color, width: 3)) : null,
      ),
      alignment: Alignment.centerLeft,
      child: contenido,
    );
    return switch (celda.tipo) {
      TipoCelda.libre when alTocarLibre != null => InkWell(onTap: alTocarLibre, child: caja),
      TipoCelda.sesion => InkWell(onTap: () => _verSesion(context, s!), child: caja),
      _ => caja,
    };
  }

  void _verSesion(BuildContext context, SesionHorario s) => showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(s.titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${Formatos.fechaCorta(s.fecha)} · ${s.inicio} a ${s.fin} · ${s.sede}'),
              Text('${Formatos.etiqueta(s.tipo)}${s.grupo != null ? ' · grupo ${s.grupo}' : ''} · ${s.participantes.length} de ${s.cupo}'),
              const SizedBox(height: 12),
              for (final p in s.participantes) Text('• $p'),
              if (s.participantes.isEmpty) const Text('Sin estudiantes.'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cerrar'))],
        ),
      );
}

/// Horario semanal de un profesional con su selector de semana. Al tocar una
/// hora libre abre "Agendar" con el profesional, el día y la hora puestos.
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
            );
          },
        ),
      ],
    );
  }
}
