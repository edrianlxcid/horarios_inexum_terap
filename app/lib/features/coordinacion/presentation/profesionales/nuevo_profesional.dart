import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/network/cliente_api.dart';
import '../../../../core/util/formatos.dart';
import '../../domain/modelos.dart';

/// Registra un profesional con sus especialidades y su horario semanal.
/// Devuelve su id. La cuenta de acceso al sistema la crea Administración.
Future<String?> mostrarNuevoProfesional(BuildContext context, ContextoCoordinacion ctx, String? area) => showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 860),
          child: _Formulario(ctx: ctx, area: area),
        ),
      ),
    );

/// Horas cada media hora, de 06:00 a 21:00.
final _horas = [
  for (var m = 6 * 60; m <= 21 * 60; m += 30) '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
];

class _Formulario extends StatefulWidget {
  const _Formulario({required this.ctx, required this.area});

  final ContextoCoordinacion ctx;
  final String? area;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  static final _cedula = RegExp(r'^[0-9]{10}$');
  static final _correo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _form = GlobalKey<FormState>();
  final _c = {for (final k in ['cedula', 'nombres', 'apellidos', 'profesion', 'telefono', 'email']) k: TextEditingController()};
  DateTime? _ingreso;
  // En orden de elección: la primera es la principal.
  final _especialidades = <String>[];
  late final _bloques = [BloqueHorario(sedeId: widget.ctx.sedes.length == 1 ? widget.ctx.sedes.first.id : null)];
  bool _almuerzo = true;
  String _almuerzoInicio = '13:00';
  String _almuerzoFin = '14:00';
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  /// Valida lo que el formulario no puede validar campo por campo.
  String? _revisar() {
    if (_especialidades.isEmpty) return 'Elige al menos una especialidad.';
    for (final b in _bloques) {
      if (b.sedeId == null) return 'Elige la sede de cada horario.';
      if (b.dias.isEmpty) return 'Elige los días de cada horario.';
      if (b.fin.compareTo(b.inicio) <= 0) return 'En cada horario, la hora de salida debe ser después de la de entrada.';
    }
    if (_almuerzo && _almuerzoFin.compareTo(_almuerzoInicio) <= 0) return 'Revisa las horas del almuerzo.';
    return null;
  }

  Future<void> _registrar() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final problema = _revisar();
    if (problema != null) return setState(() => _error = problema);
    final jornadas = [for (final b in _bloques) ...b.jornadas];
    // El almuerzo se aplica a cada día cuya jornada lo contiene.
    final pausas = !_almuerzo
        ? const <Map<String, Object?>>[]
        : [
            for (final d in {for (final j in jornadas) j['dia'] as int})
              if (jornadas.any((j) => j['dia'] == d && (j['inicio'] as String).compareTo(_almuerzoInicio) <= 0 &&
                  (j['fin'] as String).compareTo(_almuerzoFin) >= 0))
                {'dia': d, 'inicio': _almuerzoInicio, 'fin': _almuerzoFin, 'tipo': 'ALMUERZO'},
          ];
    setState(() => _guardando = true);
    try {
      final id = await Dependencias.de(context).coordinacion.crearProfesional({
        'cedula': _t('cedula'),
        'nombres': _t('nombres'),
        'apellidos': _t('apellidos'),
        'profesion': _t('profesion'),
        'telefono': _t('telefono'),
        'email': _t('email'),
        'fecha_ingreso': _ingreso == null ? null : Formatos.fechaIso(_ingreso!),
        'especialidades': _especialidades,
        'jornadas': jornadas,
        'pausas': pausas,
      });
      if (mounted) Navigator.pop(context, id);
    } on ErrorApi catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardando = false;
      });
    }
  }

  Widget _campo(String clave, String etiqueta, {String? Function(String)? validar, bool obligatorio = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _c[clave],
          decoration: InputDecoration(labelText: obligatorio ? '$etiqueta *' : etiqueta),
          validator: (v) {
            final t = (v ?? '').trim();
            if (obligatorio && t.isEmpty) return 'Obligatorio';
            return t.isEmpty || validar == null ? null : validar(t);
          },
        ),
      );

  Widget _hora(String valor, ValueChanged<String> alCambiar) => DropdownButton<String>(
        value: valor,
        isDense: true,
        items: [for (final h in _horas) DropdownMenuItem(value: h, child: Text(h))],
        onChanged: (v) => setState(() => alCambiar(v!)),
      );

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final especialidades = widget.ctx.especialidadesDeArea(widget.area);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Nuevo profesional'),
          subtitle: const Text('Con sus especialidades y su horario de trabajo'),
          trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ),
        Expanded(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Text('Datos', style: titulo),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _campo('nombres', 'Nombres', obligatorio: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _campo('apellidos', 'Apellidos', obligatorio: true)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _campo('cedula', 'Cédula', obligatorio: true,
                          validar: (t) => _cedula.hasMatch(t) ? null : 'Debe tener 10 dígitos'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _campo('profesion', 'Profesión', obligatorio: true)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _campo('telefono', 'Teléfono')),
                    const SizedBox(width: 10),
                    Expanded(child: _campo('email', 'Correo', validar: (t) => _correo.hasMatch(t) ? null : 'Correo no válido')),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_ingreso == null ? 'Fecha de ingreso (opcional)' : 'Ingresa el ${Formatos.fechaCorta(Formatos.fechaIso(_ingreso!))}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: context, initialDate: DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime(DateTime.now().year + 1));
                      if (d != null) setState(() => _ingreso = d);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text('Especialidades *', style: titulo),
                const Text('La primera que elijas queda como principal.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in especialidades)
                      FilterChip(
                        label: Text(e.nombre),
                        selected: _especialidades.contains(e.id),
                        onSelected: (s) => setState(() => s ? _especialidades.add(e.id) : _especialidades.remove(e.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Horario de trabajo *', style: titulo),
                for (final (i, b) in _bloques.indexed) _Bloque(
                  bloque: b,
                  sedes: widget.ctx.sedes,
                  hora: _hora,
                  alCambiar: () => setState(() {}),
                  alQuitar: _bloques.length == 1 ? null : () => setState(() => _bloques.removeAt(i)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _bloques.add(BloqueHorario(sedeId: _bloques.last.sedeId, dias: {6}, fin: '13:00'))),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar otro horario (otra sede u otras horas)'),
                  ),
                ),
                Row(
                  children: [
                    Checkbox(value: _almuerzo, onChanged: (v) => setState(() => _almuerzo = v!)),
                    const Text('Almuerzo de '),
                    _hora(_almuerzoInicio, (v) => _almuerzoInicio = v),
                    const Text(' a '),
                    _hora(_almuerzoFin, (v) => _almuerzoFin = v),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _guardando ? null : _registrar, child: const Text('Registrar profesional')),
        ),
      ],
    );
  }
}

/// Un horario: sede, días y horas de entrada y salida.
class _Bloque extends StatelessWidget {
  const _Bloque({required this.bloque, required this.sedes, required this.hora, required this.alCambiar, this.alQuitar});

  final BloqueHorario bloque;
  final List<Opcion> sedes;
  final Widget Function(String valor, ValueChanged<String> alCambiar) hora;
  final VoidCallback alCambiar;
  final VoidCallback? alQuitar;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Sede '),
                DropdownButton<String>(
                  value: bloque.sedeId,
                  hint: const Text('Elige'),
                  isDense: true,
                  items: [for (final s in sedes) DropdownMenuItem(value: s.id, child: Text(s.nombre))],
                  onChanged: (v) {
                    bloque.sedeId = v;
                    alCambiar();
                  },
                ),
                const SizedBox(width: 16),
                const Text('de '),
                hora(bloque.inicio, (v) => bloque.inicio = v),
                const Text(' a '),
                hora(bloque.fin, (v) => bloque.fin = v),
                const Spacer(),
                if (alQuitar != null) IconButton(tooltip: 'Quitar este horario', onPressed: alQuitar, icon: const Icon(Icons.delete_outline)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                for (final MapEntry(key: d, value: letra) in inicialesDias.entries)
                  FilterChip(
                    label: Text(letra),
                    tooltip: nombresDias[d],
                    showCheckmark: false,
                    selected: bloque.dias.contains(d),
                    onSelected: (s) {
                      s ? bloque.dias.add(d) : bloque.dias.remove(d);
                      alCambiar();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
