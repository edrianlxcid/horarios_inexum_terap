import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';

/// Agenda a un paciente: elige paciente, valoración o matrícula, terapeuta,
/// día y una hora libre (o un grupo con cupo). Las reglas las valida la base.
Future<bool?> mostrarAgendar(
  BuildContext context, {
  required ContextoCoordinacion ctx,
  String? area,
  DateTime? dia,
  String? pacienteId,
  String? pacienteNombre,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: _Agendar(ctx: ctx, area: area, dia: dia ?? DateTime.now(), pacienteId: pacienteId, pacienteNombre: pacienteNombre),
      ),
    ),
  );
}

class _Agendar extends StatefulWidget {
  const _Agendar({required this.ctx, required this.area, required this.dia, this.pacienteId, this.pacienteNombre});

  final ContextoCoordinacion ctx;
  final String? area;
  final DateTime dia;
  final String? pacienteId;
  final String? pacienteNombre;

  @override
  State<_Agendar> createState() => _AgendarState();
}

class _AgendarState extends State<_Agendar> {
  String? _pacienteId;
  String? _pacienteNombre;
  List<Map<String, dynamic>> _matriculas = const [];
  String _destino = 'VALORACION'; // 'VALORACION' o el id de una matrícula
  String? _terapeuta;
  late DateTime _dia = widget.dia;
  String? _hora;
  bool _guardando = false;

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
    final ficha = await Dependencias.de(context).coordinacion.paciente(id);
    if (!mounted) return;
    setState(() => _matriculas = (ficha['matriculas'] as List)
        .cast<Map<String, dynamic>>()
        .where((m) => m['estado'] == 'EN_CURSO' && (m['por_agendar'] as int) > 0)
        .toList());
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
    final terapeutas = widget.ctx.terapeutasDeArea(_areaDestino ?? widget.area);
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
              const Text('1. Paciente'),
              if (_pacienteId != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_pacienteNombre ?? ''),
                  trailing: widget.pacienteId == null
                      ? TextButton(onPressed: () => setState(() => _pacienteId = null), child: const Text('Cambiar'))
                      : null,
                )
              else
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (p) => '${p['apellidos']} ${p['nombres']} (${p['codigo_historia']})',
                  optionsBuilder: (texto) async {
                    if (texto.text.trim().length < 2) return const [];
                    final r = await api.pacientes(q: texto.text.trim(), area: widget.area);
                    return (r['filas'] as List).cast<Map<String, dynamic>>();
                  },
                  onSelected: (p) => _elegirPaciente(p['id'] as String, '${p['nombres']} ${p['apellidos']}'),
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
                  _terapeuta = null;
                  _hora = null;
                }),
              ),
              const SizedBox(height: 16),
              const Text('3. Terapeuta'),
              DropdownButton<String>(
                isExpanded: true,
                value: terapeutas.any((t) => t.id == _terapeuta) ? _terapeuta : null,
                hint: const Text('Elige un terapeuta'),
                items: [for (final t in terapeutas) DropdownMenuItem(value: t.id, child: Text('${t.nombre} · ${t.extra['profesion']}'))],
                onChanged: (v) => setState(() {
                  _terapeuta = v;
                  _hora = null;
                }),
              ),
              const SizedBox(height: 16),
              const Text('4. Día y hora'),
              SelectorDia(dia: _dia, texto: Formatos.fechaLarga(_dia), alCambiar: (d) => setState(() {
                _dia = d;
                _hora = null;
              })),
              if (_terapeuta != null)
                Cargador<List<HoraDisponible>>(
                  key: ValueKey('$_terapeuta${Formatos.fechaIso(_dia)}'),
                  cargar: () => api.disponibilidad(_terapeuta!, _dia),
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
                              _ => '${h.hora} · ${Formatos.etiqueta(h.estado)}',
                            }),
                            selected: _hora == h.hora,
                            onSelected: h.agendable ? (_) => setState(() => _hora = h.hora) : null,
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _pacienteId == null || _terapeuta == null || _hora == null || _guardando ? null : _confirmar,
            child: Text(_hora == null ? 'Elige una hora' : 'Agendar el ${Formatos.fechaCorta(Formatos.fechaIso(_dia))} a las $_hora'),
          ),
        ),
      ],
    );
  }
}
