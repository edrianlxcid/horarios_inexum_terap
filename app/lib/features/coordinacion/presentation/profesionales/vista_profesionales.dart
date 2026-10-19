import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../coordinacion_comun.dart';
import 'nuevo_profesional.dart';

/// Profesionales del alcance con especialidades, sedes y carga de la semana.
class VistaProfesionales extends StatefulWidget {
  const VistaProfesionales({super.key});

  @override
  State<VistaProfesionales> createState() => _VistaProfesionalesState();
}

class _VistaProfesionalesState extends State<VistaProfesionales> {
  final _busqueda = TextEditingController();
  String _q = '';
  String? _sede;
  int _version = 0;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _nuevo(AmbienteCoordinacion amb) async {
    final id = await mostrarNuevoProfesional(context, amb.ctx, amb.area);
    if (id == null || !mounted) return;
    setState(() => _version++);
    await abrirProfesional(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    return Column(
      children: [
        EncabezadoPagina(
          titulo: 'Profesionales',
          subtitulo: 'Carga de esta semana · toca uno para ver su ficha y horario',
          acciones: [
            if (amb.ctx.puedeRegistrarProfesionales)
              FilledButton.icon(onPressed: () => _nuevo(amb), icon: const Icon(Icons.person_add_alt), label: const Text('Nuevo profesional')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _busqueda,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nombre, profesión o cédula'),
                  onSubmitted: (v) => setState(() => _q = v.trim()),
                ),
              ),
              FiltroLista<String>(
                todos: 'Todas las sedes',
                valor: _sede,
                opciones: [for (final s in amb.ctx.sedes) (s.id, s.nombre)],
                alCambiar: (v) => setState(() => _sede = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Cargador<List<ProfesionalFila>>(
            key: ValueKey('$_q$_sede$_version'),
            cargar: () => api.profesionales(q: _q, area: amb.area, sede: _sede),
            construir: (context, lista, _) {
              if (lista.isEmpty) return const Aviso(icono: Icons.search_off, texto: 'No hay profesionales con esos filtros.');
              return Column(
                children: [
                  Expanded(child: _ListaProfesionales(lista: lista)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(alignment: Alignment.centerRight, child: Text('${lista.length} profesionales')),
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

class _ListaProfesionales extends StatelessWidget {
  const _ListaProfesionales({required this.lista});

  final List<ProfesionalFila> lista;

  @override
  Widget build(BuildContext context) {
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return ListView.separated(
            itemCount: lista.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = lista[i];
              return ListTile(
                leading: CircleAvatar(backgroundColor: p.color, radius: 6),
                title: Text(p.nombre),
                subtitle: Text('${p.profesion} · ${p.sedes.join(', ')}'),
                trailing: Text('${(p.ocupacion * 100).round()} %'),
                onTap: () => abrirProfesional(context, p.id),
              );
            },
          );
        }
        return TablaDesplazable(
          tabla: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 24,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 60,
            columns: const [
              DataColumn(label: Text('Profesional')),
              DataColumn(label: Text('Especialidades')),
              DataColumn(label: Text('Sede')),
              DataColumn(label: Text('Horas de trabajo'), numeric: true),
              DataColumn(label: Text('Ocupación de la semana')),
              DataColumn(label: Text('Estudiantes (30 días)'), numeric: true),
              DataColumn(label: Text('Cuenta')),
            ],
            rows: [
              for (final p in lista)
                DataRow(
                  onSelectChanged: (_) => abrirProfesional(context, p.id),
                  cells: [
                    DataCell(Row(
                      children: [
                        CircleAvatar(radius: 5, backgroundColor: p.color),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text(p.nombre), Text(p.profesion, style: gris)],
                        ),
                      ],
                    )),
                    DataCell(Text(p.especialidades.join(', '))),
                    DataCell(Text(p.sedes.join(', '))),
                    DataCell(Text('${Formatos.numero(p.horasSemana)} h')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avance(valor: p.horasOcupadas, total: p.horasSemana, ancho: 90),
                        Text('  ${p.sesionesSemana} ses.', style: gris),
                      ],
                    )),
                    DataCell(Text('${p.pacientes}')),
                    DataCell(p.tieneCuenta
                        ? const Tooltip(message: 'Tiene cuenta de acceso', child: Icon(Icons.verified_user_outlined, size: 18))
                        : Text('Sin cuenta', style: gris)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
