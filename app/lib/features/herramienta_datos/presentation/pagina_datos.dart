import 'package:flutter/material.dart';

import '../../../core/network/cliente_api.dart';
import '../data/datos_api.dart';
import '../domain/modelos.dart';
import 'vista_tabla.dart';

/// Pantalla principal de la herramienta de datos: menú de módulos y tablas
/// a la izquierda (o en un cajón en pantallas angostas) y la tabla elegida.
class PaginaDatos extends StatefulWidget {
  const PaginaDatos({
    super.key,
    required this.api,
    this.titulo = 'Datos iSmart',
    this.subtitulo = 'Herramienta de desarrollo · datos ficticios',
    this.tablaInicial = 'personas.pacientes',
  });

  final DatosApi api;
  final String titulo;
  final String subtitulo;
  final String tablaInicial;

  @override
  State<PaginaDatos> createState() => _PaginaDatosState();
}

class _PaginaDatosState extends State<PaginaDatos> {
  List<Tabla>? _tablas;
  String? _error;
  Tabla? _actual;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final tablas = await widget.api.tablas();
      setState(() {
        _tablas = tablas;
        _actual ??= tablas.where((t) => t.id == widget.tablaInicial).firstOrNull ?? tablas.first;
      });
    } on ErrorApi catch (e) {
      setState(() => _error = e.mensaje);
    }
  }

  void _elegir(Tabla tabla, {bool cerrarCajon = false}) {
    setState(() => _actual = tabla);
    if (cerrarCajon) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final amplio = ancho >= 900;

    if (_error != null) return _PantallaError(mensaje: _error!, reintentar: _cargar);
    if (_tablas == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final menu = _MenuTablas(
      titulo: widget.titulo,
      subtitulo: widget.subtitulo,
      tablas: _tablas!,
      actual: _actual,
      filtro: _filtro,
      alFiltrar: (v) => setState(() => _filtro = v),
      alElegir: (t) => _elegir(t, cerrarCajon: !amplio),
    );

    final contenido = _actual == null
        ? const SizedBox.shrink()
        : VistaTabla(key: ValueKey(_actual!.id), api: widget.api, tabla: _actual!);

    if (amplio) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 290, child: menu),
            const VerticalDivider(width: 1),
            Expanded(child: contenido),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_actual?.titulo ?? 'Datos', overflow: TextOverflow.ellipsis),
        bottom: _actual == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_actual!.modulo, style: Theme.of(context).textTheme.labelMedium),
                  ),
                ),
              ),
      ),
      drawer: Drawer(width: 300, child: SafeArea(child: menu)),
      body: contenido,
    );
  }
}

class _MenuTablas extends StatelessWidget {
  const _MenuTablas({
    required this.titulo,
    required this.subtitulo,
    required this.tablas,
    required this.actual,
    required this.filtro,
    required this.alFiltrar,
    required this.alElegir,
  });

  final List<Tabla> tablas;
  final Tabla? actual;
  final String filtro;
  final ValueChanged<String> alFiltrar;
  final ValueChanged<Tabla> alElegir;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final f = filtro.toLowerCase();
    final visibles = tablas.where((t) => f.isEmpty || t.titulo.toLowerCase().contains(f) || t.modulo.toLowerCase().contains(f));
    final porModulo = <String, List<Tabla>>{};
    for (final t in visibles) {
      porModulo.putIfAbsent(t.esquema, () => []).add(t);
    }
    final modulos = ordenModulos.where(porModulo.containsKey).toList();

    return Material(
      color: tema.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(
              children: [
                Icon(Icons.dataset_outlined, color: tema.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(titulo, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(subtitulo, style: tema.textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar tabla', prefixIcon: Icon(Icons.search, size: 20)),
              onChanged: alFiltrar,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final m in modulos) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
                    child: Text(
                      (nombresModulos[m] ?? m).toUpperCase(),
                      style: tema.textTheme.labelSmall?.copyWith(letterSpacing: 0.8, color: tema.colorScheme.primary),
                    ),
                  ),
                  for (final t in porModulo[m]!)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      selected: actual?.id == t.id,
                      selectedTileColor: tema.colorScheme.secondaryContainer,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      title: Text(t.titulo, overflow: TextOverflow.ellipsis),
                      trailing: t.soloLectura ? Icon(Icons.visibility_outlined, size: 16, color: tema.hintColor) : null,
                      onTap: () => alElegir(t),
                    ).paddingHorizontal(8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PantallaError extends StatelessWidget {
  const _PantallaError({required this.mensaje, required this.reintentar});

  final String mensaje;
  final VoidCallback reintentar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(mensaje, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Enciende la API con "dart_frog dev" dentro de la carpeta backend.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: reintentar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on Widget {
  Widget paddingHorizontal(double valor) => Padding(padding: EdgeInsets.symmetric(horizontal: valor), child: this);
}
