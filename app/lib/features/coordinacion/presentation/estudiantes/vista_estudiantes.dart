import 'package:flutter/material.dart';

import '../../../../core/dependencias.dart';
import '../../../../core/util/formatos.dart';
import '../../../../core/widgets/comunes.dart';
import '../../domain/modelos.dart';
import '../coordinacion_comun.dart';
import 'nuevo_estudiante.dart';

/// Todos los estudiantes del alcance con su contrato, programa y avance.
/// Filtros por sede, estado, profesional y programa; búsqueda libre.
class VistaEstudiantes extends StatefulWidget {
  const VistaEstudiantes({super.key});

  @override
  State<VistaEstudiantes> createState() => _VistaEstudiantesState();
}

class _VistaEstudiantesState extends State<VistaEstudiantes> {
  final _busqueda = TextEditingController();
  var _filtro = const FiltroEstudiantes();
  int _version = 0;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _nuevo(ContextoCoordinacion ctx) async {
    final id = await mostrarNuevoEstudiante(context, ctx);
    if (id == null || !mounted) return;
    setState(() => _version++);
    await abrirEstudiante(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).coordinacion;
    final amb = AmbienteCoordinacion.de(context);
    final ctx = amb.ctx;
    return Column(
      children: [
        EncabezadoPagina(
          titulo: 'Estudiantes',
          subtitulo: 'Toca un estudiante para ver su ficha completa',
          acciones: [
            FilledButton.icon(onPressed: () => _nuevo(ctx), icon: const Icon(Icons.person_add_alt), label: const Text('Nuevo estudiante')),
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
                width: 340,
                child: TextField(
                  controller: _busqueda,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Nombre, historia, contrato o representante',
                    suffixIcon: _filtro.q.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Borrar búsqueda',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _busqueda.clear();
                              _filtro = _filtro.con(q: '');
                            }),
                          ),
                  ),
                  onSubmitted: (v) => setState(() => _filtro = _filtro.con(q: v.trim())),
                ),
              ),
              FiltroLista<String>(
                todos: 'Todas las sedes',
                valor: _filtro.sede,
                opciones: [for (final s in ctx.sedes) (s.id, s.nombre)],
                alCambiar: (v) => setState(() => _filtro = _filtro.con(sede: () => v)),
              ),
              FiltroLista<String>(
                todos: 'Todos los estados',
                valor: _filtro.estado,
                opciones: [for (final e in FiltroEstudiantes.estados) (e, Formatos.etiqueta(e))],
                alCambiar: (v) => setState(() => _filtro = _filtro.con(estado: () => v)),
              ),
              FiltroLista<String>(
                todos: 'Todos los profesionales',
                valor: _filtro.profesional,
                opciones: [for (final t in ctx.terapeutasDeArea(amb.area)) (t.id, t.nombre)],
                alCambiar: (v) => setState(() => _filtro = _filtro.con(profesional: () => v)),
              ),
              FiltroLista<String>(
                todos: 'Todos los programas',
                valor: _filtro.programa,
                opciones: [for (final p in ctx.programasDeArea(amb.area)) (p.id, p.nombre)],
                alCambiar: (v) => setState(() => _filtro = _filtro.con(programa: () => v)),
              ),
              if (!_filtro.vacio)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _busqueda.clear();
                    _filtro = const FiltroEstudiantes();
                  }),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Quitar filtros'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Cargador<PaginaEstudiantes>(
            key: ValueKey('$_filtro$_version'),
            cargar: () => api.estudiantes(_filtro, area: amb.area),
            construir: (context, p, _) {
              if (p.filas.isEmpty) {
                return const Aviso(icono: Icons.search_off, texto: 'No hay estudiantes con esos filtros.');
              }
              return Column(
                children: [
                  Expanded(child: _ListaEstudiantes(filas: p.filas)),
                  Paginacion(
                    texto: '${p.total} estudiantes',
                    pagina: p.pagina,
                    paginas: p.paginas,
                    alCambiar: (n) => setState(() => _filtro = _filtro.enPagina(n)),
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

/// Tabla en pantallas anchas; lista compacta en el celular.
class _ListaEstudiantes extends StatelessWidget {
  const _ListaEstudiantes({required this.filas});

  final List<EstudianteFila> filas;

  @override
  Widget build(BuildContext context) {
    final gris = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return ListView.separated(
            itemCount: filas.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = filas[i];
              final programa = e.programas.firstOrNull;
              return ListTile(
                title: Text(e.nombreCompleto),
                subtitle: Text([
                  e.historia,
                  e.contrato?.codigo ?? 'sin contrato',
                  if (programa != null) '${programa.programa} ${programa.realizadas}/${programa.contratadas}',
                ].join(' · ')),
                trailing: Etiqueta(Formatos.etiqueta(e.estado), tono: tonoEstadoEstudiante(e.estado)),
                onTap: () => abrirEstudiante(context, e.id),
              );
            },
          );
        }
        return TablaDesplazable(
          tabla: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 24,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 64,
            columns: const [
              DataColumn(label: Text('Estudiante')),
              DataColumn(label: Text('Edad')),
              DataColumn(label: Text('Contrato')),
              DataColumn(label: Text('Programa y avance')),
              DataColumn(label: Text('Terapeuta')),
              DataColumn(label: Text('Próxima sesión')),
              DataColumn(label: Text('Estado')),
            ],
            rows: [
              for (final e in filas)
                DataRow(
                  onSelectChanged: (_) => abrirEstudiante(context, e.id),
                  cells: [
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(e.nombreCompleto), Text('${e.historia} · ${e.sede}', style: gris)],
                    )),
                    DataCell(Text(Formatos.edad(e.edadMeses))),
                    DataCell(e.contrato == null
                        ? Text('Sin contrato', style: gris)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [Text(e.contrato!.codigo), Text(Formatos.etiqueta(e.contrato!.estado), style: gris)],
                          )),
                    DataCell(_Programas(programas: e.programas)),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(e.terapeutas ?? '—', overflow: TextOverflow.ellipsis, maxLines: 2),
                    )),
                    DataCell(Text(e.proximaSesion == null ? '—' : Formatos.fechaHora(e.proximaSesion))),
                    DataCell(Etiqueta(Formatos.etiqueta(e.estado), tono: tonoEstadoEstudiante(e.estado))),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Programas extends StatelessWidget {
  const _Programas({required this.programas});

  final List<ProgramaAvance> programas;

  @override
  Widget build(BuildContext context) {
    if (programas.isEmpty) return Text('Sin programa en curso', style: TextStyle(color: Theme.of(context).hintColor));
    final p = programas.first;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${p.programa}${programas.length > 1 ? '  +${programas.length - 1}' : ''}'),
        const SizedBox(height: 4),
        Avance(valor: p.realizadas, total: p.contratadas, ancho: 90),
      ],
    );
  }
}
