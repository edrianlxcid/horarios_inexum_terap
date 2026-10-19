import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../agenda/agendar_dialogo.dart';
import '../../../recorrido/domain/recorrido.dart';
import '../../../recorrido/presentation/linea_de_tiempo.dart';
import '../coordinacion_comun.dart';
import 'recorrido_estudiante.dart';

/// Ficha completa del estudiante: su recorrido (valoración inicial → programa
/// → valoración final), datos, representantes, contratos, asistencia, demanda
/// y la línea de tiempo de sus sesiones.
class FichaEstudiante extends StatelessWidget {
  const FichaEstudiante({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    return Cargador<Map<String, dynamic>>(
      cargar: () => api.estudiante(id),
      construir: (context, e, recargar) {
        final nombre = '${e['nombres']} ${e['apellidos']}';
        return Column(
          children: [
            EncabezadoPagina(
              titulo: nombre,
              subtitulo: '${e['codigo_historia']} · ${Formatos.edad(e['edad_meses'] as int?)} · Sede ${e['sede']}',
              acciones: [
                Etiqueta(Formatos.etiqueta(e['estado'] as String?), tono: tonoEstadoEstudiante(e['estado'] as String?)),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await mostrarAgendar(context, ctx: amb.ctx, area: amb.area, pacienteId: id, pacienteNombre: nombre);
                    if (ok == true) recargar();
                  },
                  icon: const Icon(Icons.event_available),
                  label: const Text('Agendar'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  RecorridoEstudiante(e: e, ctx: amb.ctx, area: amb.area, alCambiar: recargar),
                  DosColumnas(
                    izquierda: [
                      _Datos(e: e),
                      _Representantes(lista: listaJson(e['representantes'])),
                      _Demanda(e: e, ctx: amb.ctx, alCambiar: recargar),
                      _Asistencia(a: e['asistencia'] as Map<String, dynamic>),
                    ],
                    derecha: [
                      _Contratos(contratos: listaJson(e['contratos']), matriculas: listaJson(e['matriculas'])),
                      _Sesiones(titulo: 'Próximas sesiones', sesiones: listaJson(e['proximas_sesiones']), vacio: 'Sin sesiones agendadas.'),
                      Seccion(
                        titulo: 'Línea de tiempo',
                        child: LineaDeTiempo(
                          sesiones: [for (final x in listaJson(e['linea_tiempo'])) SesionLinea.fromJson(x)],
                          alTocar: (s) => abrirProfesional(context, s.profesionalId),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Datos extends StatelessWidget {
  const _Datos({required this.e});

  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    return Seccion(
      titulo: 'Datos del estudiante',
      child: Column(
        children: [
          Dato('Cédula', e['cedula'] as String?),
          Dato('Nacimiento', '${Formatos.fechaCorta(e['fecha_nacimiento'] as String?)} (${Formatos.edad(e['edad_meses'] as int?)})'),
          Dato('Sexo', switch (e['sexo']) { 'F' => 'Femenino', 'M' => 'Masculino', _ => null }),
          Dato('Sede', e['sede'] as String?),
          Dato('Dirección', e['direccion'] as String?),
          Dato('Registrado', Formatos.fechaCorta(e['registrado_en'] as String?)),
          if (e['observaciones'] != null) Dato('Observaciones', e['observaciones'] as String?),
        ],
      ),
    );
  }
}

class _Representantes extends StatelessWidget {
  const _Representantes({required this.lista});

  final List<Map<String, dynamic>> lista;

  @override
  Widget build(BuildContext context) {
    final gris = TextStyle(color: Theme.of(context).hintColor);
    return Seccion(
      titulo: 'Representantes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lista.isEmpty) const Text('Sin representantes.'),
          for (final r in lista)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['nombres']} ${r['apellidos']} · ${Formatos.etiqueta(r['parentesco'] as String?)}'
                      '${r['es_principal'] == true ? ' (principal)' : ''}'),
                  Text(
                    [
                      'C.I. ${r['cedula']}',
                      r['telefono'] ?? 'sin teléfono',
                      r['email'] ?? 'sin correo',
                      r['tiene_cuenta'] == true ? 'usa el portal' : 'sin cuenta en el portal',
                    ].join(' · '),
                    style: gris,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Demanda extends StatelessWidget {
  const _Demanda({required this.e, required this.ctx, required this.alCambiar});

  final Map<String, dynamic> e;
  final ContextoCoordinacion ctx;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    return Seccion(
      titulo: 'Nivel de demanda',
      accion: TextButton(
        onPressed: () async {
          if (await _clasificar(context, e['id'] as String, ctx)) alCambiar();
        },
        child: const Text('Clasificar'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e['demanda'] as String? ?? 'Sin clasificar', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (e['motivo_demanda'] != null) Text(e['motivo_demanda'] as String),
        ],
      ),
    );
  }
}

class _Asistencia extends StatelessWidget {
  const _Asistencia({required this.a});

  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final asistio = a['asistio'] as int, falta = a['falta'] as int, justificada = a['justificada'] as int;
    final total = asistio + falta + justificada;
    Widget numero(String texto, int n, Tono tono) => Column(
          children: [
            Text('$n', style: Theme.of(context).textTheme.headlineSmall),
            Etiqueta(texto, tono: tono),
          ],
        );
    return Seccion(
      titulo: 'Asistencia${total == 0 ? '' : ' · ${(asistio * 100 / total).round()} %'}',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          numero('Asistió', asistio, Tono.bien),
          numero('Faltas', falta, Tono.mal),
          numero('Justificadas', justificada, Tono.alerta),
        ],
      ),
    );
  }
}

/// Cada contrato con los programas (matrículas) que cubre.
class _Contratos extends StatelessWidget {
  const _Contratos({required this.contratos, required this.matriculas});

  final List<Map<String, dynamic>> contratos;
  final List<Map<String, dynamic>> matriculas;

  @override
  Widget build(BuildContext context) {
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 13);
    return Seccion(
      titulo: 'Contratos y programas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (contratos.isEmpty) const Text('Sin contratos todavía (prospecto).'),
          for (final (i, c) in contratos.indexed) ...[
            if (i > 0) const Divider(height: 24),
            Row(
              children: [
                Text(c['codigo'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Etiqueta(Formatos.etiqueta(c['estado'] as String?), tono: tonoContrato(c['estado'] as String?)),
                const Spacer(),
                Text(Formatos.dinero(c['valor_total'] as num?)),
              ],
            ),
            Text(
              '${Formatos.etiqueta(c['tipo'] as String?)} · ${Formatos.fechaCorta(c['vigente_desde'] as String?)} al '
              '${Formatos.fechaCorta(c['vigente_hasta'] as String?)} · firmó ${c['firmante']}',
              style: gris,
            ),
            for (final m in matriculas.where((m) => m['contrato_id'] == c['id']))
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(m['programa'] as String)),
                        Avance(valor: m['realizadas'] as int, total: m['contratadas'] as int, ancho: 100),
                      ],
                    ),
                    Text(
                      [
                        Formatos.etiqueta(m['estado'] as String?),
                        if (m['fase'] != null) m['fase'] as String,
                        if (m['grupo'] != null) 'grupo ${m['grupo']}',
                        '${m['agendadas']} agendadas',
                        '${m['por_agendar']} por agendar',
                      ].join(' · '),
                      style: gris,
                    ),
                    if (m['terapeutas'] != null) Text('Con ${m['terapeutas']}', style: gris),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Sesiones extends StatelessWidget {
  const _Sesiones({required this.titulo, required this.sesiones, required this.vacio});

  final String titulo;
  final List<Map<String, dynamic>> sesiones;
  final String vacio;

  @override
  Widget build(BuildContext context) {
    return Seccion(
      titulo: titulo,
      child: Column(
        children: [
          if (sesiones.isEmpty) Align(alignment: Alignment.centerLeft, child: Text(vacio)),
          for (final s in sesiones)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${Formatos.fechaHora(s['inicio'] as String?)} · ${s['programa'] ?? Formatos.etiqueta(s['tipo'] as String?)}'),
              subtitle: Text('${s['terapeuta']}${s['numero_sesion'] != null ? ' · sesión ${s['numero_sesion']}' : ''}'
                  '${s['observacion'] != null ? ' · Nota: ${s['observacion']}' : ''}'),
              trailing: s['asistencia'] == 'PENDIENTE'
                  ? null
                  : Etiqueta(Formatos.etiqueta(s['asistencia'] as String?), tono: tonoAsistencia(s['asistencia'] as String?)),
              onTap: () => abrirProfesional(context, s['profesional_id'] as String),
            ),
        ],
      ),
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
