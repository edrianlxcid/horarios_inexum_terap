import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';
import 'agendar_dialogo.dart';

/// Ficha del paciente para coordinación: datos, representantes, matrículas,
/// próximas sesiones y nivel de demanda.
Future<void> mostrarPacienteCoordinacion(BuildContext context, String id, ContextoCoordinacion ctx, String? area) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: _Ficha(id: id, ctx: ctx, area: area),
      ),
    ),
  );
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.id, required this.ctx, required this.area});

  final String id;
  final ContextoCoordinacion ctx;
  final String? area;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    return Cargador<Map<String, dynamic>>(
      cargar: () => api.paciente(id),
      construir: (context, p, recargar) {
        List<Map<String, dynamic>> lista(String k) => (p[k] as List).cast<Map<String, dynamic>>();
        final nombre = '${p['nombres']} ${p['apellidos']}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(nombre),
              subtitle: Text([p['codigo_historia'], 'C.I. ${p['cedula'] ?? '—'}', 'nació ${Formatos.fechaCorta(p['fecha_nacimiento'] as String?)}',
                p['sede'], Formatos.etiqueta(p['estado'] as String?)].join(' · ')),
              trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  TituloSeccion(
                    'Demanda: ${p['demanda'] ?? 'sin clasificar'}',
                    accion: TextButton(
                      onPressed: () async {
                        if (await _clasificar(context, id, ctx)) recargar();
                      },
                      child: const Text('Clasificar'),
                    ),
                  ),
                  if (p['motivo_demanda'] != null) Text(p['motivo_demanda'] as String),
                  const TituloSeccion('Representantes'),
                  for (final r in lista('representantes'))
                    Text('${r['nombres']} ${r['apellidos']} (${Formatos.etiqueta(r['parentesco'] as String?)}) · '
                        'C.I. ${r['cedula']} · ${r['telefono'] ?? 'sin teléfono'} · ${r['email'] ?? 'sin correo'}'
                        '${r['tiene_cuenta'] == true ? '' : ' · sin cuenta en el portal'}'),
                  const TituloSeccion('Matrículas'),
                  if (lista('matriculas').isEmpty) const Text('Sin matrículas (prospecto).'),
                  for (final m in lista('matriculas'))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m['programa']} · ${m['contrato']}'),
                      subtitle: Text('Realizadas ${m['realizadas']} · agendadas ${m['agendadas']} · por agendar ${m['por_agendar']} '
                          'de ${m['contratadas']}${m['fase'] != null ? ' · ${m['fase']}' : ''}'),
                      trailing: Etiqueta(Formatos.etiqueta(m['estado'] as String?), tono: m['estado'] == 'EN_CURSO' ? Tono.bien : Tono.neutro),
                    ),
                  TituloSeccion(
                    'Próximas sesiones',
                    accion: TextButton.icon(
                      onPressed: () async {
                        final ok = await mostrarAgendar(context, ctx: ctx, area: area, pacienteId: id, pacienteNombre: nombre);
                        if (ok == true) recargar();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agendar'),
                    ),
                  ),
                  for (final s in lista('proximas_sesiones'))
                    Text('${Formatos.fechaHora(s['inicio'] as String?)} · ${s['programa'] ?? Formatos.etiqueta(s['tipo'] as String?)} · '
                        '${s['terapeuta']}${s['numero_sesion'] != null ? ' · sesión ${s['numero_sesion']}' : ''}'),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<bool> _clasificar(BuildContext context, String pacienteId, ContextoCoordinacion ctx) async {
  String? nivel;
  final motivo = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Nivel de demanda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final n in ctx.nivelesDemanda)
                  ChoiceChip(label: Text(n.nombre), selected: nivel == n.id, onSelected: (_) => setState(() => nivel = n.id)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: motivo, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo (qué observaste)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    ),
  );
  if (ok != true || nivel == null || !context.mounted) return false;
  return ejecutarConAviso(
    context,
    () => Dependencias.de(context).coordinacion.clasificarDemanda(pacienteId, nivel!, motivo.text.trim()),
    exito: 'Demanda clasificada',
  );
}

/// Registra un paciente nuevo con su representante principal.
Future<bool> mostrarNuevoPaciente(BuildContext context, ContextoCoordinacion ctx) async {
  final campos = {
    for (final c in ['nombres', 'apellidos', 'cedula', 'direccion', 'rep_cedula', 'rep_nombres', 'rep_apellidos', 'rep_telefono', 'rep_email'])
      c: TextEditingController(),
  };
  DateTime? nacimiento;
  var sede = ctx.sedes.firstOrNull?.id;
  var parentesco = 'MADRE';
  var sexo = 'F';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        Widget campo(String clave, String etiqueta) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(controller: campos[clave], decoration: InputDecoration(labelText: etiqueta)),
            );
        return AlertDialog(
          title: const Text('Nuevo paciente'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  campo('nombres', 'Nombres *'),
                  campo('apellidos', 'Apellidos *'),
                  campo('cedula', 'Cédula del paciente (opcional)'),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cake_outlined),
                          label: Text(nacimiento == null ? 'Fecha de nacimiento *' : Formatos.fechaCorta(Formatos.fechaIso(nacimiento!))),
                          onPressed: () async {
                            final d = await showDatePicker(context: c, initialDate: DateTime(2021), firstDate: DateTime(2000), lastDate: DateTime.now());
                            if (d != null) setState(() => nacimiento = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: sexo,
                        items: const [DropdownMenuItem(value: 'F', child: Text('Niña')), DropdownMenuItem(value: 'M', child: Text('Niño'))],
                        onChanged: (v) => setState(() => sexo = v!),
                      ),
                    ],
                  ),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: sede,
                    items: [for (final s in ctx.sedes) DropdownMenuItem(value: s.id, child: Text('Sede ${s.nombre}'))],
                    onChanged: (v) => setState(() => sede = v),
                  ),
                  campo('direccion', 'Dirección'),
                  const TituloSeccion('Representante principal'),
                  campo('rep_cedula', 'Cédula *'),
                  campo('rep_nombres', 'Nombres *'),
                  campo('rep_apellidos', 'Apellidos *'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: parentesco,
                    items: [
                      for (final p in ['MADRE', 'PADRE', 'ABUELA', 'ABUELO', 'TIA', 'TIO', 'TUTOR', 'OTRO'])
                        DropdownMenuItem(value: p, child: Text(Formatos.etiqueta(p))),
                    ],
                    onChanged: (v) => setState(() => parentesco = v!),
                  ),
                  campo('rep_telefono', 'Teléfono'),
                  campo('rep_email', 'Correo'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return false;
  String? t(String c) => campos[c]!.text.trim().isEmpty ? null : campos[c]!.text.trim();
  return ejecutarConAviso(
    context,
    () => Dependencias.de(context).coordinacion.crearPaciente({
      'nombres': t('nombres'),
      'apellidos': t('apellidos'),
      'cedula': t('cedula'),
      'fecha_nacimiento': nacimiento == null ? null : Formatos.fechaIso(nacimiento!),
      'sexo': sexo,
      'direccion': t('direccion'),
      'sede_id': sede,
      'representante': {
        'cedula': t('rep_cedula'),
        'nombres': t('rep_nombres'),
        'apellidos': t('rep_apellidos'),
        'parentesco': parentesco,
        'telefono': t('rep_telefono'),
        'email': t('rep_email'),
      },
    }),
    exito: 'Paciente registrado',
  );
}
