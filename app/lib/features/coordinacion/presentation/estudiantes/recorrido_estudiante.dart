import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../../recorrido/domain/recorrido.dart';
import '../../../recorrido/presentation/linea_de_tiempo.dart';
import '../../domain/modelos.dart';
import '../agenda/agendar_dialogo.dart';
import 'valoracion_dialogos.dart';

/// Recorrido del estudiante en tres pasos: valoración inicial → programa →
/// valoración final, con lo previsto, lo hecho y lo que toca hacer.
class RecorridoEstudiante extends StatelessWidget {
  const RecorridoEstudiante({super.key, required this.e, required this.ctx, required this.area, required this.alCambiar});

  /// Ficha del estudiante (respuesta de la API).
  final Map<String, dynamic> e;
  final ContextoCoordinacion ctx;
  final String? area;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final etapa = e['etapa'] as String;
    final valoraciones = [for (final v in listaJson(e['valoraciones'])) ValoracionProceso.fromJson(v)];
    final inicial = valoraciones.where((v) => v.tipo == 'INICIAL').lastOrNull;
    final fin = valoraciones.where((v) => v.tipo == 'FINAL').lastOrNull;
    final programas = [for (final m in listaJson(e['matriculas'])) if (m['estado'] != 'CANCELADA') m];
    const despuesDelPrograma = {'POR_VALORACION_FINAL', 'VALORACION_FINAL', 'FINALIZADO'};

    return Seccion(
      titulo: 'Recorrido',
      accion: EtiquetaEtapa(etapa),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Paso(
            numero: 1,
            titulo: 'Valoración inicial',
            hecho: inicial != null && !inicial.enCurso,
            activo: etapa == 'POR_VALORAR' || etapa == 'VALORACION_INICIAL',
            child: inicial == null
                ? _Accion(
                    texto: 'Todo estudiante pasa primero por valoración (de 1 a 20 sesiones entre especialidades).',
                    boton: 'Abrir valoración inicial',
                    alPulsar: () => _abrir(context, 'INICIAL'),
                  )
                : _Valoracion(v: inicial, e: e, ctx: ctx, area: area, alCambiar: alCambiar),
          ),
          _Paso(
            numero: 2,
            titulo: 'Programa',
            hecho: despuesDelPrograma.contains(etapa) && programas.isNotEmpty,
            activo: etapa == 'EN_PROGRAMA' || etapa == 'POR_INGRESAR',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (etapa == 'POR_INGRESAR')
                  const Text('Valorado: falta asignarle su programa (contrato y horario).'),
                for (final m in programas)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('${m['programa']} · ${Formatos.etiqueta(m['estado'] as String?)}')),
                        Avance(valor: m['realizadas'] as int, total: m['contratadas'] as int, ancho: 90),
                      ],
                    ),
                  ),
                if (programas.isEmpty && etapa != 'POR_INGRESAR')
                  Text('Empieza al cerrar la valoración inicial.', style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          _Paso(
            numero: 3,
            titulo: 'Valoración final',
            hecho: fin != null && !fin.enCurso,
            activo: etapa == 'POR_VALORACION_FINAL' || etapa == 'VALORACION_FINAL',
            ultimo: true,
            child: fin != null && (fin.enCurso || etapa != 'POR_VALORACION_FINAL')
                ? _Valoracion(v: fin, e: e, ctx: ctx, area: area, alCambiar: alCambiar)
                : etapa == 'POR_VALORACION_FINAL'
                    ? _Accion(
                        texto: 'Terminó las sesiones de su programa: toca la valoración final (de 1 a 20 sesiones).',
                        boton: 'Abrir valoración final',
                        alPulsar: () => _abrir(context, 'FINAL'),
                      )
                    : Text('Al terminar el programa.', style: TextStyle(color: Theme.of(context).hintColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _abrir(BuildContext context, String tipo) async {
    final plan = await mostrarPlanValoracion(context, ctx, tipo: tipo);
    if (plan == null || !context.mounted) return;
    final api = Dependencias.de(context).coordinacion;
    if (await ejecutarConAviso(context, () => api.abrirValoracion(e['id'] as String, tipo, plan), exito: 'Valoración abierta')) {
      alCambiar();
    }
  }
}

/// Un paso del recorrido: número (o visto si está hecho), título y detalle.
class _Paso extends StatelessWidget {
  const _Paso({
    required this.numero,
    required this.titulo,
    required this.hecho,
    required this.activo,
    required this.child,
    this.ultimo = false,
  });

  final int numero;
  final String titulo;
  final bool hecho, activo, ultimo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final color = hecho ? c.primary : activo ? c.tertiary : c.outline;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: hecho || activo ? color : Colors.transparent,
                foregroundColor: c.surface,
                child: hecho
                    ? const Icon(Icons.check, size: 16)
                    : Text('$numero', style: TextStyle(fontSize: 12, color: activo ? c.surface : color)),
              ),
              if (!ultimo) Expanded(child: Container(width: 2, color: c.outlineVariant)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, color: activo ? c.tertiary : null)),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion({required this.texto, required this.boton, required this.alPulsar});

  final String texto, boton;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(onPressed: alPulsar, icon: const Icon(Icons.play_arrow), label: Text(boton)),
        ],
      );
}

/// Detalle de una valoración: por especialidad, hechas / agendadas / previstas.
/// En curso: agendar, ajustar lo previsto, cerrar o anular.
class _Valoracion extends StatelessWidget {
  const _Valoracion({required this.v, required this.e, required this.ctx, required this.area, required this.alCambiar});

  final ValoracionProceso v;
  final Map<String, dynamic> e;
  final ContextoCoordinacion ctx;
  final String? area;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 13);
    final api = Dependencias.de(context).coordinacion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final x in v.especialidades)
          Text('${x.especialidad}: ${x.realizadas} hechas · ${x.agendadas} agendadas · de ${x.previstas} previstas'
              '${v.enCurso && x.porAgendar > 0 ? ' (${faltan(x.porAgendar)} por agendar)' : ''}'),
        if (!v.enCurso) ...[
          const SizedBox(height: 4),
          Text(
            [
              nombresResultados[v.resultado] ?? Formatos.etiqueta(v.resultado),
              if (v.programaRecomendado != null) v.programaRecomendado!,
              'cerrada el ${Formatos.fechaCorta(v.cerradoEn)}',
            ].join(' · '),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (v.conclusion != null) Text(v.conclusion!, style: gris),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  onPressed: v.especialidades.every((x) => x.porAgendar == 0)
                      ? null
                      : () async {
                          final ok = await mostrarAgendar(context,
                              ctx: ctx, area: area, pacienteId: e['id'] as String, pacienteNombre: '${e['nombres']} ${e['apellidos']}');
                          if (ok == true) alCambiar();
                        },
                  icon: const Icon(Icons.event_available),
                  label: const Text('Agendar sesión'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final plan = await mostrarPlanValoracion(context, ctx,
                        tipo: v.tipo,
                        actual: {for (final x in v.especialidades) x.subAreaId: x.previstas},
                        minimos: {for (final x in v.especialidades) x.subAreaId: x.realizadas + x.agendadas});
                    if (plan == null || !context.mounted) return;
                    if (await ejecutarConAviso(context, () => api.ajustarValoracion(v.id, plan), exito: 'Sesiones previstas actualizadas')) {
                      alCambiar();
                    }
                  },
                  child: const Text('Ajustar sesiones'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final cierre = await mostrarCerrarValoracion(context, ctx, v);
                    if (cierre == null || !context.mounted) return;
                    final ok = await ejecutarConAviso(
                      context,
                      () => api.cerrarValoracion(v.id,
                          resultado: cierre.resultado, conclusion: cierre.conclusion, programaRecomendadoId: cierre.programaRecomendadoId),
                      exito: 'Valoración cerrada',
                    );
                    if (ok) alCambiar();
                  },
                  child: const Text('Cerrar valoración'),
                ),
                if (v.realizadas == 0 && v.agendadas == 0)
                  TextButton(
                    onPressed: () async {
                      if (await ejecutarConAviso(context, () => api.cancelarValoracion(v.id), exito: 'Valoración anulada')) alCambiar();
                    },
                    child: const Text('Anular'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
