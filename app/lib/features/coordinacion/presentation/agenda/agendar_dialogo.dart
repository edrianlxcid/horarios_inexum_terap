import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';

/// Agenda a un estudiante: elige estudiante, valoración o matrícula, terapeuta,
/// día y una hora libre (o un grupo con cupo). Las reglas las valida la base.
/// Desde el horario semanal llega con el terapeuta, el día y la hora ya elegidos.
Future<bool?> mostrarAgendar(
  BuildContext context, {
  required ContextoCoordinacion ctx,
  String? area,
  DateTime? dia,
  String? pacienteId,
  String? pacienteNombre,
  String? profesionalId,
  String? hora,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: _Agendar(
          ctx: ctx,
          area: area,
          dia: dia ?? DateTime.now(),
          pacienteId: pacienteId,
          pacienteNombre: pacienteNombre,
          profesionalId: profesionalId,
          hora: hora,
        ),
      ),
    ),
  );
}

class _Agendar extends StatefulWidget {
  const _Agendar({
    required this.ctx,
    required this.area,
    required this.dia,
    this.pacienteId,
    this.pacienteNombre,
    this.profesionalId,
    this.hora,
  });

  final ContextoCoordinacion ctx;
  final String? area;
  final DateTime dia;
  final String? pacienteId;
  final String? pacienteNombre;
  final String? profesionalId;
  final String? hora;

  @override
  State<_Agendar> createState() => _AgendarState();
}

class _AgendarState extends State<_Agendar> {
  String? _pacienteId;
  String? _pacienteNombre;
  List<Map<String, dynamic>> _matriculas = const [];
  String _destino = 'VALORACION'; // 'VALORACION' o el id de una matrícula
  late String? _terapeuta = widget.profesionalId;
  late DateTime _dia = widget.dia;
  late String? _hora = widget.hora;
  final _nota = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.pacienteId != null) _elegirPaciente(widget.pacienteId!, widget.pacienteNombre ?? '');
  }

  Future<void> _elegirPaciente(String id, String nombre) async {
    setState(() {
      _pacienteId = id;
      _pacienteNombre = nombre;
      _matriculas = const [];
      _destino = 'VALORACION';
    });
    final ficha = await Dependencias.de(context).coordinacion.estudiante(id);
    if (!mounted) return;
    setState(() {
      _matriculas = (ficha['matriculas'] as List)
          .cast<Map<String, dynamic>>()
          .where((m) => m['estado'] == 'EN_CURSO' && (m['por_agendar'] as int) > 0)
          .toList();
      // Si se llegó desde el horario de alguien que no valora, se agenda su
      // programa: se elige la primera matrícula del área de ese profesional.
      final elegido = widget.ctx.terapeutas.where((t) => t.id == _terapeuta).firstOrNull;
      if (elegido != null && elegido.extra['valora'] != true) {
        final areas = (elegido.extra['areas'] as List).cast<String>();
        final matricula = _matriculas.where((m) => areas.contains(m['area_id'])).firstOrNull;
        if (matricula != null) _destino = matricula['id'] as String;
      }
    });
  }

  String? get _areaDestino => _destino == 'VALORACION'
      ? null
      : _matriculas.firstWhere((m) => m['id'] == _destino)['area_id'] as String?;

  Future<void> _confirmar() async {
    setState(() => _guardando = true);
    final ok = await ejecutarConAviso(
      context,
      () => Dependencias.de(context).coordinacion.agendar(
            pacienteId: _pacienteId!,
            profesionalId: _terapeuta!,
            inicio: '${Formatos.fechaIso(_dia)}T$_hora',
            tipo: _destino == 'VALORACION' ? 'VALORACION' : 'PROGRAMA',
            matriculaId: _destino == 'VALORACION' ? null : _destino,
            observacion: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
          ),
      exito: 'Sesión agendada',
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final valoracion = _destino == 'VALORACION';
    // Valoraciones: solo quienes valoran (son de Neuro, pero también se valora,
    // como excepción, a estudiantes de Estimulación temprana).
    final terapeutas = valoracion ? widget.ctx.terapeutasQueValoran : widget.ctx.terapeutasDeArea(_areaDestino ?? widget.area);
    // Si cambia lo que se agenda, el terapeuta elegido sigue solo si está en la nueva lista.
    final elegido = terapeutas.where((t) => t.id == _terapeuta).firstOrNull;
    final terapeuta = elegido?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Agendar sesión'),
          trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const Text('1. Estudiante'),
              if (_pacienteId != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_pacienteNombre ?? ''),
                  trailing: widget.pacienteId == null
                      ? TextButton(onPressed: () => setState(() => _pacienteId = null), child: const Text('Cambiar'))
                      : null,
                )
              else
                Autocomplete<EstudianteFila>(
                  displayStringForOption: (p) => '${p.nombreCompleto} (${p.historia})',
                  optionsBuilder: (texto) async {
                    if (texto.text.trim().length < 2) return const [];
                    final r = await api.estudiantes(FiltroEstudiantes(q: texto.text.trim()), area: widget.area);
                    return r.filas;
                  },
                  onSelected: (p) => _elegirPaciente(p.id, '${p.nombres} ${p.apellidos}'),
                  fieldViewBuilder: (context, controlador, foco, _) => TextField(
                    controller: controlador,
                    focusNode: foco,
                    decoration: const InputDecoration(hintText: 'Escribe al menos 2 letras del nombre'),
                  ),
                ),
              const SizedBox(height: 16),
              const Text('2. Qué se agenda'),
              DropdownButton<String>(
                isExpanded: true,
                value: _destino,
                items: [
                  const DropdownMenuItem(value: 'VALORACION', child: Text('Valoración')),
                  for (final m in _matriculas)
                    DropdownMenuItem(
                      value: m['id'] as String,
                      child: Text('${m['programa']} · quedan ${m['por_agendar']} por agendar (${m['contrato']})'),
                    ),
                ],
                onChanged: _pacienteId == null ? null : (v) => setState(() {
                  _destino = v!;
                }),
              ),
              const SizedBox(height: 16),
              const Text('3. Terapeuta'),
              DropdownButton<String>(
                isExpanded: true,
                value: terapeuta,
                hint: const Text('Elige un terapeuta'),
                items: [for (final t in terapeutas) DropdownMenuItem(value: t.id, child: Text('${t.nombre} · ${t.extra['profesion']}'))],
                onChanged: (v) => setState(() {
                  _terapeuta = v;
                  _hora = null;
                }),
              ),
              Text(
                [
                  if (valoracion) 'Solo aparecen quienes hacen valoraciones.',
                  if (elegido != null) 'Turnos de ${elegido.extra['minutos_turno'] ?? 60} minutos.',
                ].join(' '),
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 16),
              const Text('4. Día y hora'),
              SelectorDia(dia: _dia, texto: Formatos.fechaLarga(_dia), alCambiar: (d) => setState(() {
                _dia = d;
                _hora = null;
              })),
              if (terapeuta != null)
                Cargador<List<HoraDisponible>>(
                  key: ValueKey('$terapeuta${Formatos.fechaIso(_dia)}'),
                  cargar: () => api.disponibilidad(terapeuta, _dia),
                  construir: (context, horas, _) {
                    if (horas.isEmpty) return const Text('El terapeuta no trabaja este día.');
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final h in horas)
                          ChoiceChip(
                            label: Text(switch (h.estado) {
                              'LIBRE' => h.hora,
                              'OCUPADO' => '${h.hora} · ${h.programa ?? 'ocupado'} ${h.ocupados}/${h.cupo}',
                              'PAUSA' => '${h.hora} · ${Formatos.etiqueta(h.pausa)}',
                              _ => '${h.hora} · ${Formatos.etiqueta(h.estado)}',
                            }),
                            selected: _hora == h.hora,
                            onSelected: h.agendable ? (_) => setState(() => _hora = h.hora) : null,
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _nota,
                decoration: const InputDecoration(labelText: '5. Nota de coordinación (opcional)', hintText: 'Solo por hoy, desde esta semana, no mover…'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _pacienteId == null || terapeuta == null || _hora == null || _guardando ? null : _confirmar,
            child: Text(_hora == null ? 'Elige una hora' : 'Agendar el ${Formatos.fechaCorta(Formatos.fechaIso(_dia))} a las $_hora'),
          ),
        ),
      ],
    );
  }
}
