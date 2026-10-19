import 'package:flutter/material.dart';

import '../network/cliente_api.dart';
import '../util/formatos.dart';

/// Carga datos de forma asíncrona y muestra cargando, error con reintento o el contenido.
/// Para volver a cargar con otros parámetros, cambia su `key` (por ejemplo, `ValueKey(dia)`).
class Cargador<T> extends StatefulWidget {
  const Cargador({super.key, required this.cargar, required this.construir});

  final Future<T> Function() cargar;
  final Widget Function(BuildContext context, T datos, VoidCallback recargar) construir;

  @override
  State<Cargador<T>> createState() => _CargadorState<T>();
}

class _CargadorState<T> extends State<Cargador<T>> {
  late Future<T> _futuro = widget.cargar();

  void _recargar() => setState(() => _futuro = widget.cargar());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _futuro,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (s.hasError) {
          final e = s.error;
          return Aviso(
            icono: Icons.error_outline,
            texto: e is ErrorApi ? e.mensaje : 'Ocurrió un error inesperado: $e',
            accion: TextButton.icon(onPressed: _recargar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          );
        }
        return widget.construir(context, s.data as T, _recargar);
      },
    );
  }
}

/// Mensaje centrado (vacío, error o información).
class Aviso extends StatelessWidget {
  const Aviso({super.key, required this.icono, required this.texto, this.accion});

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: 12), accion!],
          ],
        ),
      ),
    );
  }
}

/// Encabezado de una página interna: flecha para volver (si hay a dónde),
/// título, subtítulo y acciones a la derecha.
class EncabezadoPagina extends StatelessWidget {
  const EncabezadoPagina({super.key, required this.titulo, this.subtitulo, this.acciones = const []});

  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          if (Navigator.of(context).canPop()) const BackButton() else const SizedBox(width: 8),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: texto.titleLarge?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if (subtitulo != null)
                  Text(subtitulo!, style: texto.bodyMedium?.copyWith(color: Theme.of(context).hintColor), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ...acciones,
        ],
      ),
    );
  }
}

/// Bloque con título dentro de una ficha.
class Seccion extends StatelessWidget {
  const Seccion({super.key, required this.titulo, required this.child, this.accion});

  final String titulo;
  final Widget child;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                ?accion,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Par "etiqueta: valor" de una ficha.
class Dato extends StatelessWidget {
  const Dato(this.etiqueta, this.valor, {super.key});

  final String etiqueta;
  final String? valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(etiqueta, style: TextStyle(color: Theme.of(context).hintColor))),
          Expanded(child: Text(valor == null || valor!.isEmpty ? '—' : valor!)),
        ],
      ),
    );
  }
}

/// Avance "x de y" con barra.
class Avance extends StatelessWidget {
  const Avance({super.key, required this.valor, required this.total, this.ancho = 120});

  final num valor;
  final num total;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: ancho,
          child: LinearProgressIndicator(value: total == 0 ? 0 : (valor / total).clamp(0, 1).toDouble(), minHeight: 6,
              borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Text('${Formatos.numero(valor)}/${Formatos.numero(total)}', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// Dos columnas en pantallas anchas; una sola en el celular.
class DosColumnas extends StatelessWidget {
  const DosColumnas({super.key, required this.izquierda, required this.derecha, this.corte = 900});

  final List<Widget> izquierda;
  final List<Widget> derecha;
  final double corte;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < corte
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...izquierda, ...derecha])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: izquierda)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: derecha)),
              ],
            ),
    );
  }
}

/// Lista desplegable compacta para filtros, con opción "todos".
class FiltroLista<T> extends StatelessWidget {
  const FiltroLista({super.key, required this.todos, required this.valor, required this.opciones, required this.alCambiar});

  final String todos;
  final T? valor;
  final List<(T, String)> opciones;
  final ValueChanged<T?> alCambiar;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T?>(
      value: opciones.any((o) => o.$1 == valor) ? valor : null,
      underline: const SizedBox.shrink(),
      isDense: true,
      items: [
        DropdownMenuItem<T?>(value: null, child: Text(todos)),
        for (final (v, texto) in opciones) DropdownMenuItem<T?>(value: v, child: Text(texto, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: alCambiar,
    );
  }
}

/// Título de sección con acción opcional a la derecha.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ?accion,
        ],
      ),
    );
  }
}

/// Etiqueta pequeña para estados (asistencia, matrícula, solicitud...).
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.tono = Tono.neutro});

  final String texto;
  final Tono tono;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (fondo, frente) = switch (tono) {
      Tono.bien => (c.primaryContainer, c.onPrimaryContainer),
      Tono.alerta => (c.tertiaryContainer, c.onTertiaryContainer),
      Tono.mal => (c.errorContainer, c.onErrorContainer),
      Tono.neutro => (c.surfaceContainerHighest, c.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: TextStyle(fontSize: 12, color: frente)),
    );
  }
}

enum Tono { bien, alerta, mal, neutro }

/// Tono de una asistencia para pintarla.
Tono tonoAsistencia(String? a) => switch (a) {
      'ASISTIO' => Tono.bien,
      'FALTA' => Tono.mal,
      'FALTA_JUSTIFICADA' || 'CANCELADA' || 'REPROGRAMADA' => Tono.alerta,
      _ => Tono.neutro,
    };

/// Muestra el resultado de una acción (o su error) en la parte inferior.
Future<bool> ejecutarConAviso(BuildContext context, Future<void> Function() accion, {String? exito}) async {
  final mensajero = ScaffoldMessenger.of(context);
  final colorError = Theme.of(context).colorScheme.error;
  try {
    await accion();
    if (exito != null) mensajero.showSnackBar(SnackBar(content: Text(exito)));
    return true;
  } on ErrorApi catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text(e.mensaje), backgroundColor: colorError));
    return false;
  }
}

/// Selector de día con flechas y botón "Hoy".
class SelectorDia extends StatelessWidget {
  const SelectorDia({super.key, required this.dia, required this.alCambiar, required this.texto});

  final DateTime dia;
  final ValueChanged<DateTime> alCambiar;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Día anterior', onPressed: () => alCambiar(dia.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
        TextButton(
          onPressed: () async {
            final elegido = await showDatePicker(context: context, initialDate: dia, firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (elegido != null) alCambiar(elegido);
          },
          child: Text(texto),
        ),
        IconButton(tooltip: 'Día siguiente', onPressed: () => alCambiar(dia.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: () => alCambiar(DateTime.now()), child: const Text('Hoy')),
      ],
    );
  }
}
