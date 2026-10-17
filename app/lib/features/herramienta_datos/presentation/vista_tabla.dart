import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/cliente_api.dart';
import '../data/datos_api.dart';
import '../domain/modelos.dart';
import 'formulario_fila.dart';

/// Lista paginada de una tabla con bÃºsqueda, y acceso al formulario.
/// En pantallas anchas muestra una tabla; en angostas, tarjetas.
class VistaTabla extends StatefulWidget {
  const VistaTabla({super.key, required this.api, required this.tabla});

  final DatosApi api;
  final Tabla tabla;

  @override
  State<VistaTabla> createState() => _VistaTablaState();
}

class _VistaTablaState extends State<VistaTabla> {
  static const _ocultas = {'empresa_id', 'creado_por', 'actualizado_por', 'actualizado_en', 'cedula_huella', 'password_hash', 'mfa_secreto'};

  PaginaFilas? _pagina;
  String? _error;
  bool _cargando = false;
  int _numero = 1;
  String _busqueda = '';
  Timer? _espera;

  Tabla get _t => widget.tabla;

  List<Columna> get _columnasVisibles => _t.columnas
      .where((c) => !_ocultas.contains(c.nombre) && !(c.esClave && c.tipo == 'uuid' && _t.clave.length == 1))
      .toList();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pagina = await widget.api.filas(_t, busqueda: _busqueda, pagina: _numero);
      if (mounted) setState(() => _pagina = pagina);
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () {
      _busqueda = texto;
      _numero = 1;
      _cargar();
    });
  }

  Future<void> _abrir([Map<String, dynamic>? fila]) async {
    final cambio = await mostrarFormulario(context, api: widget.api, tabla: _t, fila: fila);
    if (cambio != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cambio)));
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final amplio = MediaQuery.sizeOf(context).width >= 700;
    final pagina = _pagina;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(amplio ? 24 : 16, amplio ? 20 : 12, amplio ? 24 : 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Con menos de 900 px el tÃ­tulo ya aparece en la barra superior.
              if (MediaQuery.sizeOf(context).width >= 900) ...[
                Text(_t.modulo.toUpperCase(), style: tema.textTheme.labelSmall?.copyWith(letterSpacing: 0.8, color: tema.colorScheme.primary)),
                const SizedBox(height: 2),
                Text(_t.titulo, style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
              if (_t.descripcion != null) ...[
                const SizedBox(height: 4),
                Text(_t.descripcion!, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: amplio ? 320 : double.infinity,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Buscarâ€¦', prefixIcon: Icon(Icons.search, size: 20)),
                      onChanged: _buscar,
                    ),
                  ),
                  if (!_t.soloLectura)
                    FilledButton.icon(onPressed: () => _abrir(), icon: const Icon(Icons.add), label: const Text('Nuevo')),
                  IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh)),
                  if (_t.soloLectura)
                    Chip(
                      avatar: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Solo lectura'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_cargando) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(
          child: _error != null
              ? _Aviso(icono: Icons.error_outline, texto: _error!, color: tema.colorScheme.error)
              : pagina == null
                  ? const SizedBox.shrink()
                  : pagina.filas.isEmpty
                      ? _Aviso(
                          icono: Icons.inbox_outlined,
                          texto: _busqueda.isEmpty ? 'Esta tabla estÃ¡ vacÃ­a.' : 'No hay resultados para "$_busqueda".',
                        )
                      : amplio
                          ? _Tabla(tabla: _t, columnas: _columnasVisibles, filas: pagina.filas, alTocar: _abrir)
                          : _Tarjetas(tabla: _t, columnas: _columnasVisibles, filas: pagina.filas, alTocar: _abrir),
        ),
        if (pagina != null && pagina.total > 0)
          _Paginacion(
            pagina: pagina,
            anterior: _numero > 1 ? () => _irA(_numero - 1) : null,
            siguiente: _numero < pagina.paginas ? () => _irA(_numero + 1) : null,
          ),
      ],
    );
  }

  void _irA(int numero) {
    setState(() => _numero = numero);
    _cargar();
  }
}

/// Valor de una celda listo para mostrar.
String textoCelda(Columna c, Map<String, dynamic> fila) {
  final valor = c.referencia != null ? (fila['${c.nombre}__etiqueta'] ?? fila[c.nombre]) : fila[c.nombre];
  if (valor == null) return 'â€”';
  if (c.tipo == 'booleano') return valor.toString() == 'true' ? 'SÃ­' : 'No';
  return valor.toString();
}

class _Tabla extends StatelessWidget {
  const _Tabla({required this.tabla, required this.columnas, required this.filas, required this.alTocar});

  final Tabla tabla;
  final List<Columna> columnas;
  final List<Map<String, dynamic>> filas;
  final ValueChanged<Map<String, dynamic>> alTocar;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 52,
            columnSpacing: 22,
            columns: [
              for (final c in columnas)
                DataColumn(
                  label: Tooltip(
                    message: c.comentario ?? c.tipoSql,
                    child: Text(c.titulo),
                  ),
                  numeric: c.tipo == 'entero' || c.tipo == 'decimal',
                ),
            ],
            rows: [
              for (final f in filas)
                DataRow(
                  onSelectChanged: (_) => alTocar(f),
                  cells: [
                    for (final c in columnas)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: _Celda(columna: c, fila: f),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Celda extends StatelessWidget {
  const _Celda({required this.columna, required this.fila});

  final Columna columna;
  final Map<String, dynamic> fila;

  @override
  Widget build(BuildContext context) {
    final texto = textoCelda(columna, fila);
    final esquema = Theme.of(context).colorScheme;
    if (columna.tipo == 'opcion' && texto != 'â€”') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: esquema.secondaryContainer, borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(fontSize: 12, color: esquema.onSecondaryContainer)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (columna.tipo == 'cifrado' && texto != 'â€”') ...[
          Icon(Icons.lock_outline, size: 14, color: esquema.primary),
          const SizedBox(width: 4),
        ],
        Flexible(child: Text(texto, overflow: TextOverflow.ellipsis, maxLines: 2)),
      ],
    );
  }
}

class _Tarjetas extends StatelessWidget {
  const _Tarjetas({required this.tabla, required this.columnas, required this.filas, required this.alTocar});

  final Tabla tabla;
  final List<Columna> columnas;
  final List<Map<String, dynamic>> filas;
  final ValueChanged<Map<String, dynamic>> alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final detalle = columnas.where((c) => !const {'nombres', 'apellidos', 'nombre'}.contains(c.nombre)).take(4).toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: filas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final f = filas[i];
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => alTocar(f),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tabla.tituloDe(f), style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  for (final c in detalle)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${c.titulo}: ', style: TextStyle(color: tema.colorScheme.onSurfaceVariant)),
                            TextSpan(text: textoCelda(c, f)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Paginacion extends StatelessWidget {
  const _Paginacion({required this.pagina, required this.anterior, required this.siguiente});

  final PaginaFilas pagina;
  final VoidCallback? anterior;
  final VoidCallback? siguiente;

  @override
  Widget build(BuildContext context) {
    final desde = (pagina.pagina - 1) * pagina.tamano + 1;
    final hasta = (desde + pagina.filas.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$desdeâ€“$hasta de ${pagina.total}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            IconButton(tooltip: 'Anterior', onPressed: anterior, icon: const Icon(Icons.chevron_left)),
            Text('${pagina.pagina} / ${pagina.paginas}'),
            IconButton(tooltip: 'Siguiente', onPressed: siguiente, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 40, color: color ?? Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
