import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../agenda/agendar_dialogo.dart';
import '../coordinacion_comun.dart';
import 'horario_semanal.dart';

/// Horarios de todos los profesionales en una semana. Sin filtro muestra un
/// resumen por día (jornada y ocupación); al elegir un profesional, su
/// grilla hora por hora, donde se puede agendar en las horas libres.
class VistaHorarios extends StatefulWidget {
  const VistaHorarios({super.key});

  @override
  State<VistaHorarios> createState() => _VistaHorariosState();
}

class _VistaHorariosState extends State<VistaHorarios> {
  DateTime _semana = DateTime.now();
  String? _sede;
  String? _profesional;
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncabezadoPagina(
          titulo: 'Horarios de los profesionales',
          subtitulo: _profesional == null ? 'Toca un profesional para ver su semana hora por hora' : 'Toca una hora libre para agendar',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectorSemana(semana: _semana, alCambiar: (d) => setState(() => _semana = d)),
              FiltroLista<String>(
                todos: 'Todas las sedes',
                valor: _sede,
                opciones: [for (final s in amb.ctx.sedes) (s.id, s.nombre)],
                alCambiar: (v) => setState(() => _sede = v),
              ),
              FiltroLista<String>(
                todos: 'Todos los profesionales',
                valor: _profesional,
                opciones: [for (final t in amb.ctx.terapeutasDeArea(amb.area)) (t.id, t.nombre)],
                alCambiar: (v) => setState(() => _profesional = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: Cargador<SemanaHorario>(
            key: ValueKey('${Formatos.fechaIso(lunesDe(_semana))}$_sede$_profesional$_version'),
            cargar: () => api.horarios(_semana, area: amb.area, sede: _sede, profesional: _profesional),
            construir: (context, semana, _) {
              if (semana.profesionales.isEmpty) {
                return const Aviso(icono: Icons.event_busy, texto: 'No hay profesionales con horario en esta semana.');
              }
              if (_profesional != null) {
                final p = semana.profesionales.first;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(radius: 6, backgroundColor: p.color),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${p.nombre} · ${p.profesion}', style: Theme.of(context).textTheme.titleMedium)),
                        TextButton.icon(
                          onPressed: () => abrirProfesional(context, p.id),
                          icon: const Icon(Icons.badge_outlined),
                          label: const Text('Ver ficha'),
                        ),
                      ],
                    ),
                    const LeyendaHorario(),
                    const SizedBox(height: 8),
                    GrillaSemanal(
                      semana: semana,
                      profesional: p,
                      alAgendar: (dia, hora) async {
                        final ok = await mostrarAgendar(context,
                            ctx: amb.ctx, area: amb.area, dia: dia, profesionalId: p.id, hora: hora);
                        if (ok == true) setState(() => _version++);
                      },
                    ),
                  ],
                );
              }
              return _ResumenSemana(semana: semana, alElegir: (p) => setState(() => _profesional = p.id));
            },
          ),
        ),
      ],
    );
  }
}

/// Una fila por profesional y una columna por día: jornada, sesiones y
/// ocupación del día; ausencias y feriados resaltados.
class _ResumenSemana extends StatelessWidget {
  const _ResumenSemana({required this.semana, required this.alElegir});

  final SemanaHorario semana;
  final ValueChanged<ProfesionalSemana> alElegir;

  @override
  Widget build(BuildContext context) {
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    return TablaDesplazable(
      tabla: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 18,
        dataRowMinHeight: 56,
        dataRowMaxHeight: 64,
        columns: [
          const DataColumn(label: Text('Profesional')),
          for (final d in semana.dias)
            DataColumn(label: Text(DateFormat('EEE d', 'es').format(d) + (semana.feriadoDel(d) != null ? ' · feriado' : ''))),
          const DataColumn(label: Text('Semana')),
        ],
        rows: [
          for (final p in semana.profesionales)
            DataRow(
              onSelectChanged: (_) => alElegir(p),
              cells: [
                DataCell(Row(
                  children: [
                    CircleAvatar(radius: 5, backgroundColor: p.color),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(p.nombre), Text(p.profesion, style: gris)],
                    ),
                  ],
                )),
                for (final d in semana.dias) DataCell(_Dia(semana: semana, profesional: p, dia: d)),
                DataCell(_Total(profesional: p, semana: semana)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dia extends StatelessWidget {
  const _Dia({required this.semana, required this.profesional, required this.dia});

  final SemanaHorario semana;
  final ProfesionalSemana profesional;
  final DateTime dia;

  @override
  Widget build(BuildContext context) {
    final f = Formatos.fechaIso(dia);
    final jornadas = profesional.jornadasDel(dia.weekday);
    if (jornadas.isEmpty) return Text('—', style: TextStyle(color: Theme.of(context).hintColor));
    final ausencia = profesional.ausenciaEn('${f}T00:00', '${f}T23:59');
    final feriado = semana.feriadoDel(dia);
    if (feriado != null) return Etiqueta(feriado.nombre, tono: Tono.alerta);
    if (ausencia != null) return Etiqueta(Formatos.etiqueta(ausencia.tipo), tono: Tono.mal);
    final horas = profesional.horasDel(dia.weekday);
    final sesiones = profesional.sesionesDel(dia);
    final ocupadas = sesiones.fold<double>(0, (s, x) => s + x.horas);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(jornadas.map((j) => '${j.inicio.substring(0, 2)}–${j.fin.substring(0, 2)}').join(', '), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 3),
        Tooltip(
          message: '${sesiones.length} sesiones · ${Formatos.numero(ocupadas)} de ${Formatos.numero(horas)} horas',
          child: SizedBox(
            width: 64,
            child: LinearProgressIndicator(value: horas == 0 ? 0 : (ocupadas / horas).clamp(0, 1), minHeight: 6,
                borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.profesional, required this.semana});

  final ProfesionalSemana profesional;
  final SemanaHorario semana;

  @override
  Widget build(BuildContext context) {
    final horas = semana.dias.fold<double>(0, (s, d) => s + profesional.horasDel(d.weekday));
    final ocupadas = profesional.sesiones.fold<double>(0, (s, x) => s + x.horas);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${profesional.sesiones.length} sesiones', style: const TextStyle(fontSize: 12)),
        Text('${Formatos.numero(ocupadas)} de ${Formatos.numero(horas)} h', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
      ],
    );
  }
}
