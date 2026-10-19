import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/network/cliente_api.dart';
import '../../../../core/util/formatos.dart';
import '../../domain/modelos.dart';

/// Registra un estudiante con su representante principal. Devuelve su id.
Future<String?> mostrarNuevoEstudiante(BuildContext context, ContextoCoordinacion ctx) => showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820), child: _Formulario(ctx: ctx)),
      ),
    );

class _Formulario extends StatefulWidget {
  const _Formulario({required this.ctx});

  final ContextoCoordinacion ctx;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  static const _parentescos = ['MADRE', 'PADRE', 'ABUELA', 'ABUELO', 'TIA', 'TIO', 'TUTOR', 'OTRO'];
  static final _cedula = RegExp(r'^[0-9]{10}$');

  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in ['nombres', 'apellidos', 'cedula', 'direccion', 'observaciones',
                     'rep_cedula', 'rep_nombres', 'rep_apellidos', 'rep_telefono', 'rep_email'])
      k: TextEditingController(),
  };
  DateTime? _nacimiento;
  late String? _sede = widget.ctx.sedes.length == 1 ? widget.ctx.sedes.first.id : null;
  String _sexo = 'F';
  String _parentesco = 'MADRE';
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

  Future<void> _registrar() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_nacimiento == null) return setState(() => _error = 'Elige la fecha de nacimiento.');
    setState(() => _guardando = true);
    try {
      final r = await Dependencias.de(context).coordinacion.crearEstudiante({
        'nombres': _t('nombres'),
        'apellidos': _t('apellidos'),
        'cedula': _t('cedula'),
        'fecha_nacimiento': Formatos.fechaIso(_nacimiento!),
        'sexo': _sexo,
        'direccion': _t('direccion'),
        'observaciones': _t('observaciones'),
        'sede_id': _sede,
        'representante': {
          'cedula': _t('rep_cedula'),
          'nombres': _t('rep_nombres'),
          'apellidos': _t('rep_apellidos'),
          'parentesco': _parentesco,
          'telefono': _t('rep_telefono'),
          'email': _t('rep_email'),
        },
      });
      if (mounted) Navigator.pop(context, r['id'] as String);
    } on ErrorApi catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardando = false;
      });
    }
  }

  Widget _campo(String clave, String etiqueta, {bool obligatorio = false, bool cedula = false, int lineas = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _c[clave],
          maxLines: lineas,
          keyboardType: cedula ? TextInputType.number : null,
          decoration: InputDecoration(labelText: obligatorio ? '$etiqueta *' : etiqueta),
          validator: (v) {
            final t = (v ?? '').trim();
            if (obligatorio && t.isEmpty) return 'Obligatorio';
            if (cedula && t.isNotEmpty && !_cedula.hasMatch(t)) return 'Debe tener 10 dígitos';
            return null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Nuevo estudiante'),
          subtitle: const Text('Queda como prospecto hasta que tenga contrato'),
          trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ),
        Expanded(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Text('Estudiante', style: titulo),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _campo('nombres', 'Nombres', obligatorio: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _campo('apellidos', 'Apellidos', obligatorio: true)),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _campo('cedula', 'Cédula (opcional)', cedula: true)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        icon: const Icon(Icons.cake_outlined),
                        label: Text(_nacimiento == null ? 'Nacimiento *' : Formatos.fechaCorta(Formatos.fechaIso(_nacimiento!))),
                        onPressed: () async {
                          final d = await showDatePicker(
                              context: context, initialDate: DateTime(DateTime.now().year - 3), firstDate: DateTime(2000), lastDate: DateTime.now());
                          if (d != null) setState(() => _nacimiento = d);
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    SegmentedButton<String>(
                      segments: const [ButtonSegment(value: 'F', label: Text('Niña')), ButtonSegment(value: 'M', label: Text('Niño'))],
                      selected: {_sexo},
                      onSelectionChanged: (s) => setState(() => _sexo = s.first),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _sede,
                        decoration: const InputDecoration(labelText: 'Sede *'),
                        items: [for (final s in widget.ctx.sedes) DropdownMenuItem(value: s.id, child: Text(s.nombre))],
                        validator: (v) => v == null ? 'Obligatorio' : null,
                        onChanged: (v) => setState(() => _sede = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _campo('direccion', 'Dirección'),
                _campo('observaciones', 'Observaciones', lineas: 2),
                const SizedBox(height: 6),
                Text('Representante principal', style: titulo),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _campo('rep_cedula', 'Cédula', obligatorio: true, cedula: true)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _parentesco,
                        decoration: const InputDecoration(labelText: 'Parentesco'),
                        items: [for (final p in _parentescos) DropdownMenuItem(value: p, child: Text(Formatos.etiqueta(p)))],
                        onChanged: (v) => setState(() => _parentesco = v!),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _campo('rep_nombres', 'Nombres', obligatorio: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _campo('rep_apellidos', 'Apellidos', obligatorio: true)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _campo('rep_telefono', 'Teléfono')),
                    const SizedBox(width: 10),
                    Expanded(child: _campo('rep_email', 'Correo')),
                  ],
                ),
                const Text('Si el representante ya está registrado (misma cédula), se vincula al existente.',
                    style: TextStyle(fontSize: 12)),
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
          child: FilledButton(onPressed: _guardando ? null : _registrar, child: const Text('Registrar estudiante')),
        ),
      ],
    );
  }
}
