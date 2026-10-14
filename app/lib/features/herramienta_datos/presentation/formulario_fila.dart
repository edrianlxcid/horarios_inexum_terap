import 'package:flutter/material.dart';

import '../../../core/network/cliente_api.dart';
import '../data/datos_api.dart';
import '../domain/modelos.dart';
import 'campo_referencia.dart';

/// Abre el formulario de un registro (nuevo si [fila] es nulo).
/// Devuelve un mensaje si algo cambió, o null si se canceló.
Future<String?> mostrarFormulario(
  BuildContext context, {
  required DatosApi api,
  required Tabla tabla,
  Map<String, dynamic>? fila,
}) {
  final formulario = FormularioFila(api: api, tabla: tabla, fila: fila);
  if (MediaQuery.sizeOf(context).width < 700) {
    return Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => formulario));
  }
  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780), child: formulario),
    ),
  );
}

class FormularioFila extends StatefulWidget {
  const FormularioFila({super.key, required this.api, required this.tabla, this.fila});

  final DatosApi api;
  final Tabla tabla;
  final Map<String, dynamic>? fila;

  @override
  State<FormularioFila> createState() => _FormularioFilaState();
}

class _FormularioFilaState extends State<FormularioFila> {
  final _form = GlobalKey<FormState>();
  final _textos = <String, TextEditingController>{};
  final _valores = <String, String?>{};
  final _iniciales = <String, String?>{};
  bool _guardando = false;
  String? _error;

  Tabla get _t => widget.tabla;
  bool get _nuevo => widget.fila == null;
  bool get _soloLectura => _t.soloLectura;

  /// Campos que se muestran: en un registro nuevo se omite el id automático.
  List<Columna> get _campos => _t.columnas.where((c) {
        if (_soloLectura) return true;
        if (_nuevo) return c.editable && !(c.esClave && c.tipo == 'uuid' && !c.requerido);
        return true;
      }).toList();

  bool _editable(Columna c) => !_soloLectura && c.editable && (_nuevo || !c.esClave);

  @override
  void initState() {
    super.initState();
    for (final c in _t.columnas) {
      var inicial = widget.fila?[c.nombre]?.toString();
      if (c.tipo == 'secreto') inicial = null;
      if (_nuevo && c.tipo == 'booleano') inicial = const {'activo', 'recibe_notificaciones'}.contains(c.nombre) ? 'true' : 'false';
      _iniciales[c.nombre] = inicial;
      _valores[c.nombre] = inicial;
      _textos[c.nombre] = TextEditingController(text: inicial ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _valor(Columna c) {
    if (const {'booleano', 'opcion', 'referencia'}.contains(c.tipo)) return _valores[c.nombre];
    final texto = _textos[c.nombre]!.text.trim();
    return texto.isEmpty ? null : texto;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final datos = <String, dynamic>{};
    for (final c in _campos.where(_editable)) {
      final v = _valor(c);
      if (c.tipo == 'secreto' && v == null) continue;
      if (_nuevo ? v != null : v != _iniciales[c.nombre]) datos[c.nombre] = v;
    }
    if (!_nuevo && datos.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_nuevo) {
        await widget.api.crear(_t, datos);
      } else {
        await widget.api.actualizar(_t, widget.fila!, datos);
      }
      if (mounted) Navigator.of(context).pop(_nuevo ? 'Registro creado' : 'Cambios guardados');
    } on ErrorApi catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final verbo = _t.archivable ? 'Archivar' : 'Eliminar';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿$verbo este registro?'),
        content: Text(
          _t.archivable
              ? 'Dejará de aparecer como activo, pero se conserva en la base con la fecha de archivo.'
              : 'Esta tabla no se archiva: el registro se borra. Si otros datos dependen de él, la base no lo permitirá.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(verbo)),
        ],
      ),
    );
    if (confirmado != true) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final resultado = await widget.api.eliminar(_t, widget.fila!);
      if (mounted) Navigator.of(context).pop('Registro $resultado');
    } on ErrorApi catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final titulo = _nuevo ? 'Nuevo registro' : _t.tituloDe(widget.fila!);
    return Scaffold(
      backgroundColor: tema.colorScheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, overflow: TextOverflow.ellipsis),
            Text('${_t.modulo} · ${_t.titulo}', style: tema.textTheme.labelMedium),
          ],
        ),
        actions: [IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
      ),
      body: Form(
        key: _form,
        child: LayoutBuilder(
          builder: (context, limites) {
            final dosColumnas = limites.maxWidth > 560;
            final anchoCorto = dosColumnas ? (limites.maxWidth - 48 - 16) / 2 : limites.maxWidth - 40;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                if (_error != null) _BannerError(mensaje: _error!),
                if (_soloLectura)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Esta tabla es de solo lectura: se calcula sola o solo admite registros nuevos del sistema.',
                        style: tema.textTheme.bodySmall),
                  ),
                Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  children: [
                    for (final c in _campos)
                      SizedBox(
                        width: c.textoLargo || !dosColumnas ? limites.maxWidth - 40 : anchoCorto,
                        child: _campo(c),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              if (!_nuevo && !_soloLectura)
                TextButton.icon(
                  onPressed: _guardando ? null : _eliminar,
                  icon: Icon(_t.archivable ? Icons.archive_outlined : Icons.delete_outline),
                  label: Text(_t.archivable ? 'Archivar' : 'Eliminar'),
                  style: TextButton.styleFrom(foregroundColor: tema.colorScheme.error),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(_soloLectura ? 'Cerrar' : 'Cancelar')),
              if (!_soloLectura) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_nuevo ? 'Crear' : 'Guardar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo(Columna c) {
    final editable = _editable(c);
    final etiqueta = '${c.titulo}${c.requerido && editable ? ' *' : ''}';
    final ayuda = c.tipo == 'cifrado'
        ? 'Se guarda cifrado en la base.'
        : c.tipo == 'secreto'
            ? (_nuevo ? 'Se guarda solo su hash.' : 'Déjalo vacío para no cambiarlo.')
            : c.comentario;
    String? requerido(String? v) => c.requerido && editable && (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;

    InputDecoration deco({Widget? sufijo, Widget? prefijo}) => InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          helperMaxLines: 3,
          suffixIcon: sufijo,
          prefixIcon: prefijo,
        );

    switch (c.tipo) {
      case 'booleano':
        return InputDecorator(
          decoration: InputDecoration(labelText: c.titulo, helperText: c.comentario, helperMaxLines: 3),
          child: Row(
            children: [
              Expanded(child: Text(_valores[c.nombre] == 'true' ? 'Sí' : 'No')),
              Switch(
                value: _valores[c.nombre] == 'true',
                onChanged: editable ? (v) => setState(() => _valores[c.nombre] = v.toString()) : null,
              ),
            ],
          ),
        );
      case 'opcion':
        return DropdownButtonFormField<String>(
          initialValue: _valores[c.nombre],
          isExpanded: true,
          decoration: deco(),
          items: [
            if (!c.requerido) const DropdownMenuItem(value: null, child: Text('—')),
            for (final o in c.opciones!) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: editable ? (v) => setState(() => _valores[c.nombre] = v) : null,
          validator: requerido,
        );
      case 'referencia':
        return CampoReferencia(
          api: widget.api,
          referencia: c.referencia!,
          etiqueta: etiqueta,
          ayuda: c.comentario,
          valorInicial: _valores[c.nombre],
          textoInicial: widget.fila?['${c.nombre}__etiqueta']?.toString() ?? _valores[c.nombre],
          habilitado: editable,
          requerido: c.requerido && editable,
          alCambiar: (v) => _valores[c.nombre] = v,
        );
      case 'fecha':
      case 'fecha_hora':
      case 'hora':
        return TextFormField(
          controller: _textos[c.nombre],
          readOnly: !editable,
          decoration: deco(
            sufijo: editable
                ? IconButton(
                    tooltip: 'Elegir',
                    icon: Icon(c.tipo == 'hora' ? Icons.schedule : Icons.calendar_today_outlined, size: 20),
                    onPressed: () => _elegirFecha(c),
                  )
                : null,
          ),
          validator: requerido,
        );
      default:
        final numerico = c.tipo == 'entero' || c.tipo == 'decimal';
        return TextFormField(
          controller: _textos[c.nombre],
          readOnly: !editable,
          obscureText: c.tipo == 'secreto',
          minLines: c.textoLargo ? 2 : 1,
          maxLines: c.textoLargo ? 6 : 1,
          keyboardType: numerico ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: deco(prefijo: c.tipo == 'cifrado' ? const Icon(Icons.lock_outline, size: 18) : null),
          validator: (v) {
            final falta = c.tipo == 'secreto' && !_nuevo ? null : requerido(v);
            if (falta != null) return falta;
            if (numerico && v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) == null) return 'Debe ser un número';
            return null;
          },
        );
    }
  }

  Future<void> _elegirFecha(Columna c) async {
    final control = _textos[c.nombre]!;
    final actual = DateTime.tryParse(control.text.replaceFirst(' ', 'T')) ?? DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    String? fecha;
    TimeOfDay? hora;
    if (c.tipo != 'hora') {
      final d = await showDatePicker(context: context, initialDate: actual, firstDate: DateTime(1900), lastDate: DateTime(2100));
      if (d == null) return;
      fecha = '${d.year}-${dos(d.month)}-${dos(d.day)}';
    }
    if (c.tipo != 'fecha' && mounted) {
      final partes = control.text.split(RegExp('[ :T]'));
      final inicial = c.tipo == 'hora' && partes.length >= 2
          ? TimeOfDay(hour: int.tryParse(partes[0]) ?? 8, minute: int.tryParse(partes[1]) ?? 0)
          : TimeOfDay(hour: actual.hour, minute: actual.minute);
      hora = await showTimePicker(context: context, initialTime: inicial);
      if (hora == null) return;
    }
    final textoHora = hora == null ? null : '${dos(hora.hour)}:${dos(hora.minute)}';
    setState(() => control.text = [?fecha, ?textoHora].join(' '));
  }
}

class _BannerError extends StatelessWidget {
  const _BannerError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: esquema.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, color: esquema.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje, style: TextStyle(color: esquema.onErrorContainer))),
        ],
      ),
    );
  }
}
