import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../coordinacion_comun.dart';

/// Pedidos de reprogramación o cancelación pendientes de respuesta.
class VistaSolicitudes extends StatelessWidget {
  const VistaSolicitudes({super.key});

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    return Column(
      children: [
        const EncabezadoPagina(titulo: 'Solicitudes de cambio', subtitulo: 'Reprogramaciones y cancelaciones pendientes'),
        Expanded(
          child: Cargador<List<Map<String, dynamic>>>(
            cargar: () => api.solicitudes(area: amb.area),
            construir: (context, solicitudes, recargar) {
              if (solicitudes.isEmpty) return const Aviso(icono: Icons.inbox, texto: 'No hay solicitudes pendientes.');
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  for (final s in solicitudes)
                    Card(
                      child: ListTile(
                        title: Text('${Formatos.etiqueta(s['tipo'] as String?)} · ${s['paciente']}'),
                        subtitle: Text('Sesión ${Formatos.fechaHora(s['sesion_inicio'] as String?)} con ${s['terapeuta']}\n'
                            'Motivo: ${s['motivo']} · pedido por ${Formatos.etiqueta(s['origen'] as String?)}'
                            '${s['propuesta_inicio'] != null ? '\nPropone: ${Formatos.fechaHora(s['propuesta_inicio'] as String?)}' : ''}'),
                        isThreeLine: true,
                        onTap: () => abrirEstudiante(context, s['paciente_id'] as String),
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
          ),
        ),
      ],
    );
  }
}
