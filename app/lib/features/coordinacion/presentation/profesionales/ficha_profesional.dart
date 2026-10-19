import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../coordinacion_comun.dart';
import '../horarios/horario_semanal.dart';

/// Ficha del profesional: datos, especialidades, horario de la semana
/// (con agendar en horas libres), ausencias y estudiantes que atiende.
class FichaProfesional extends StatelessWidget {
  const FichaProfesional({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    return Cargador<Map<String, dynamic>>(
      cargar: () => api.profesional(id),
      construir: (context, p, _) {
        final gris = TextStyle(color: Theme.of(context).hintColor);
        final jornadas = listaJson(p['jornadas']);
        final ausencias = listaJson(p['ausencias']);
        final pacientes = listaJson(p['pacientes']);
        return Column(
          children: [
            EncabezadoPagina(
              titulo: '${p['nombres']} ${p['apellidos']}',
              subtitulo: p['profesion'] as String,
              acciones: [CircleAvatar(radius: 8, backgroundColor: colorDe(p['color'] as String?))],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  DosColumnas(
                    izquierda: [
                      Seccion(
                        titulo: 'Datos',
                        child: Column(
                          children: [
                            Dato('Cédula', p['cedula'] as String?),
                            Dato('Teléfono', p['telefono'] as String?),
                            Dato('Correo', p['email'] as String?),
                            Dato('Ingreso', p['fecha_ingreso'] == null ? null : Formatos.fechaCorta(p['fecha_ingreso'] as String?)),
                            Dato('Cuenta', p['tiene_cuenta'] == true ? 'Tiene acceso al sistema' : 'Sin cuenta (la crea Administración)'),
                          ],
                        ),
                      ),
                    ],
                    derecha: [
                      Seccion(
                        titulo: 'Especialidades y jornada',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final e in listaJson(p['especialidades']))
                                  Chip(
                                    label: Text('${e['nombre']}${e['es_principal'] == true ? ' (principal)' : ''}'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final j in jornadas)
                              Text('${nombresDias[j['dia']]}: ${j['inicio']} a ${j['fin']} · ${j['sede']}'),
                            if (ausencias.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Ausencias próximas', style: gris),
                              for (final a in ausencias)
                                Text('${Formatos.etiqueta(a['tipo'] as String?)}: ${Formatos.fechaHora(a['desde'] as String?)} '
                                    'a ${Formatos.fechaHora(a['hasta'] as String?)}'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  Seccion(titulo: 'Horario', child: HorarioDeProfesional(profesionalId: id)),
                  Seccion(
                    titulo: 'Estudiantes que atiende (últimos 60 días y próximas sesiones)',
                    child: Column(
                      children: [
                        if (pacientes.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('Sin estudiantes por ahora.')),
                        for (final e in pacientes)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${e['nombre']} · ${e['codigo_historia']}'),
                            subtitle: Text('${e['programas']} · ${e['sesiones_60d']} sesiones'
                                '${e['proxima'] != null ? ' · próxima ${Formatos.fechaHora(e['proxima'] as String?)}' : ''}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => abrirEstudiante(context, e['id'] as String),
                          ),
                      ],
                    ),
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
