import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';
import 'agendar_dialogo.dart';
import 'paciente_coordinacion.dart';

/// Coordinación: agenda del día, pacientes y solicitudes de cambio.
/// Si coordina varias áreas, elige con cuál trabajar ("cambiar de interfaz").
class PaginaCoordinacion extends StatefulWidget {
  const PaginaCoordinacion({super.key});

  @override
  State<PaginaCoordinacion> createState() => _PaginaCoordinacionState();
}

class _PaginaCoordinacionState extends State<PaginaCoordinacion> {
  String? _area;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    return Cargador<ContextoCoordinacion>(
      cargar: api.contexto,
      construir: (context, ctx, _) {
        final area = ctx.areas.length == 1 ? ctx.areas.first.id : _area;
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Text('Área: '),
                    if (ctx.areas.length > 1)
                      DropdownButton<String?>(
                        value: _area,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Todas mis áreas')),
                          for (final a in ctx.areas) DropdownMenuItem(value: a.id, child: Text(a.nombre)),
                        ],
                        onChanged: (v) => setState(() => _area = v),
                      )
                    else
                      Text(ctx.areas.firstOrNull?.nombre ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 16),
                    Expanded(child: Text('Sedes: ${ctx.sedes.map((s) => s.nombre).join(', ')}', overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              const TabBar(tabs: [Tab(text: 'Agenda'), Tab(text: 'Pacientes'), Tab(text: 'Solicitudes')]),
              Expanded(
                child: TabBarView(
                  children: [
                    _TabAgenda(key: ValueKey('agenda$area'), ctx: ctx, area: area),
                    _TabPacientes(key: ValueKey('pacientes$area'), ctx: ctx, area: area),
                    _TabSolicitudes(key: ValueKey('solicitudes$area'), area: area),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TabAgenda extends StatefulWidget {
  const _TabAgenda({super.key, required this.ctx, required this.area});

  final ContextoCoordinacion ctx;
  final String? area;

  @override
  State<_TabAgenda> createState() => _TabAgendaState();
}

class _TabAgendaState extends State<_TabAgenda> {
  DateTime _dia = DateTime.now();
  String? _terapeuta;
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final terapeutas = widget.ctx.terapeutasDeArea(widget.area);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              SelectorDia(dia: _dia, texto: Formatos.fechaLarga(_dia), alCambiar: (d) => setState(() => _dia = d)),
              DropdownButton<String?>(
                value: _terapeuta,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos los terapeutas')),
                  for (final t in terapeutas) DropdownMenuItem(value: t.id, child: Text(t.nombre)),
                ],
                onChanged: (v) => setState(() => _terapeuta = v),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await mostrarAgendar(context, ctx: widget.ctx, area: widget.area, dia: _dia);
                  if (ok == true) setState(() => _version++);
                },
                icon: const Icon(Icons.add),
                label: const Text('Agendar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Cargador<List<SesionCoordinacion>>(
            key: ValueKey('${Formatos.fechaIso(_dia)}$_terapeuta$_version'),
            cargar: () => api.agenda(_dia, area: widget.area, profesional: _terapeuta),
            construir: (context, sesiones, recargar) {
              if (sesiones.isEmpty) return const Aviso(icono: Icons.event_busy, texto: 'No hay sesiones este día.');
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final s in sesiones)
                    Card(
                      child: ListTile(
                        leading: Text(Formatos.hora(s.inicio), style: Theme.of(context).textTheme.titleMedium),
                        title: Text('${s.terapeuta} · ${s.programa ?? Formatos.etiqueta(s.tipo)}'
                            '${s.grupo != null ? ' · ${s.grupo}' : ''}'),
                        subtitle: Text('${s.sede} · ${s.participantes.length}/${s.cupo} · '
                            '${s.participantes.map((p) => p['paciente']).join(', ')}'),
                        trailing: s.estado == 'PROGRAMADA'
                            ? IconButton(
                                tooltip: 'Cancelar sesión',
                                icon: const Icon(Icons.event_busy),
                                onPressed: () async {
                                  final motivo = await _pedirMotivo(context);
                                  if (motivo == null || !context.mounted) return;
                                  if (await ejecutarConAviso(context, () => api.cancelarSesion(s.id, motivo), exito: 'Sesión cancelada')) {
                                    recargar();
                                  }
                                },
                              )
                            : Etiqueta(Formatos.etiqueta(s.estado), tono: s.estado == 'CANCELADA' ? Tono.mal : Tono.neutro),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TabPacientes extends StatefulWidget {
  const _TabPacientes({super.key, required this.ctx, required this.area});

  final ContextoCoordinacion ctx;
  final String? area;

  @override
  State<_TabPacientes> createState() => _TabPacientesState();
}

class _TabPacientesState extends State<_TabPacientes> {
  final _busqueda = TextEditingController();
  String _q = '';
  int _pagina = 1;
  int _version = 0;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busqueda,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nombre, historia clínica o cédula exacta'),
                  onSubmitted: (v) => setState(() {
                    _q = v.trim();
                    _pagina = 1;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  if (await mostrarNuevoPaciente(context, widget.ctx)) setState(() => _version++);
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Nuevo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Cargador<Map<String, dynamic>>(
            key: ValueKey('$_q$_pagina$_version'),
            cargar: () => api.pacientes(q: _q, area: widget.area, pagina: _pagina),
            construir: (context, r, _) {
              final filas = (r['filas'] as List).cast<Map<String, dynamic>>();
              final total = r['total'] as int;
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        for (final p in filas)
                          ListTile(
                            title: Text('${p['apellidos']} ${p['nombres']}'),
                            subtitle: Text([p['codigo_historia'], Formatos.edad(p['edad_meses'] as int?), p['sede'],
                              p['programas'] ?? 'sin programa activo'].join(' · ')),
                            trailing: Etiqueta(Formatos.etiqueta(p['estado'] as String?),
                                tono: p['estado'] == 'ACTIVO' ? Tono.bien : Tono.neutro),
                            onTap: () async {
                              await mostrarPacienteCoordinacion(context, p['id'] as String, widget.ctx, widget.area);
                              setState(() => _version++);
                            },
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('$total pacientes'),
                      IconButton(onPressed: _pagina > 1 ? () => setState(() => _pagina--) : null, icon: const Icon(Icons.chevron_left)),
                      Text('$_pagina'),
                      IconButton(
                        onPressed: _pagina * 25 < total ? () => setState(() => _pagina++) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TabSolicitudes extends StatelessWidget {
  const _TabSolicitudes({super.key, required this.area});

  final String? area;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    return Cargador<List<Map<String, dynamic>>>(
      cargar: () => api.solicitudes(area: area),
      construir: (context, solicitudes, recargar) {
        if (solicitudes.isEmpty) return const Aviso(icono: Icons.inbox, texto: 'No hay solicitudes pendientes.');
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final s in solicitudes)
              Card(
                child: ListTile(
                  title: Text('${Formatos.etiqueta(s['tipo'] as String?)} · ${s['paciente']}'),
                  subtitle: Text('Sesión ${Formatos.fechaHora(s['sesion_inicio'] as String?)} con ${s['terapeuta']}\n'
                      'Motivo: ${s['motivo']} · pedido por ${Formatos.etiqueta(s['origen'] as String?)}'
                      '${s['propuesta_inicio'] != null ? '\nPropone: ${Formatos.fechaHora(s['propuesta_inicio'] as String?)}' : ''}'),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      for (final (estado, texto) in const [('RECHAZADA', 'Rechazar'), ('APROBADA', 'Aprobar')])
                        TextButton(
                          onPressed: () async {
                            final ok = await ejecutarConAviso(
                              context,
                              () => api.resolverSolicitud(s['id'] as String, estado),
                              exito: estado == 'APROBADA'
                                  ? 'Aprobada. Si era reprogramación, agenda la nueva fecha.'
                                  : 'Solicitud rechazada',
                            );
                            if (ok) recargar();
                          },
                          child: Text(texto),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<String?> _pedirMotivo(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Cancelar sesión'),
      content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Motivo')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cancelar sesión')),
      ],
    ),
  );
  return ok == true && c.text.trim().isNotEmpty ? c.text.trim() : null;
}
