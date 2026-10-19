import 'package:flutter/material.dart';

import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/recorrido.dart';

/// Etiqueta con la etapa del recorrido.
class EtiquetaEtapa extends StatelessWidget {
  const EtiquetaEtapa(this.etapa, {super.key});

  final String? etapa;

  @override
  Widget build(BuildContext context) {
    final tono = switch (etapa) {
      'EN_PROGRAMA' || 'FINALIZADO' => Tono.bien,
      'VALORACION_INICIAL' || 'VALORACION_FINAL' => Tono.neutro,
      'RETIRADO' => Tono.mal,
      _ => Tono.alerta, // pide una acción de coordinación
    };
    return Etiqueta(nombresEtapas[etapa] ?? Formatos.etiqueta(etapa), tono: tono);
  }
}

/// Sesiones del paciente de la más reciente a la más antigua: etapa, número
/// de sesión, con quién, si asistió y qué se trabajó. [alTocar] (opcional)
/// se llama al tocar una sesión, por ejemplo para abrir su nota.
class LineaDeTiempo extends StatelessWidget {
  const LineaDeTiempo({super.key, required this.sesiones, this.alTocar, this.vacio = 'Todavía no tiene sesiones.'});

  final List<SesionLinea> sesiones;
  final void Function(SesionLinea sesion)? alTocar;
  final String vacio;

  @override
  Widget build(BuildContext context) {
    if (sesiones.isEmpty) return Align(alignment: Alignment.centerLeft, child: Text(vacio));
    final colores = Theme.of(context).colorScheme;
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    return Column(
      children: [
        for (final (i, s) in sesiones.indexed)
          InkWell(
            onTap: alTocar == null ? null : () => alTocar!(s),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Punto y línea vertical: el color marca la etapa.
                  SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        Container(width: 2, height: 8, color: i == 0 ? Colors.transparent : colores.outlineVariant),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.esValoracion ? colores.tertiary : colores.primary,
                          ),
                        ),
                        Expanded(child: Container(width: 2, color: i == sesiones.length - 1 ? Colors.transparent : colores.outlineVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('${Formatos.fechaHora(s.inicio)} · ${s.titulo}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                              if (s.asistencia != 'PENDIENTE')
                                Etiqueta(Formatos.etiqueta(s.asistencia), tono: tonoAsistencia(s.asistencia)),
                            ],
                          ),
                          Text([?s.numeroTexto, s.terapeuta, if (s.observacion != null) 'Nota: ${s.observacion}'].join(' · '), style: gris),
                          if (s.trabajado != null) Text('Trabajado: ${s.trabajado}', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
