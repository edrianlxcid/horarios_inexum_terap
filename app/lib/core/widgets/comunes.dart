import 'package:flutter/material.dart';

import '../network/cliente_api.dart';

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
