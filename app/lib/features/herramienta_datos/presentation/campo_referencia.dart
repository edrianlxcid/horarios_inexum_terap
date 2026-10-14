import 'package:flutter/material.dart';

import '../../../core/network/cliente_api.dart';
import '../data/datos_api.dart';
import '../domain/modelos.dart';

/// Campo para elegir un registro de otra tabla buscándolo por su nombre.
class CampoReferencia extends StatefulWidget {
  const CampoReferencia({
    super.key,
    required this.api,
    required this.referencia,
    required this.etiqueta,
    required this.valorInicial,
    required this.textoInicial,
    required this.habilitado,
    required this.requerido,
    required this.alCambiar,
    this.ayuda,
  });

  final DatosApi api;
  final Referencia referencia;
  final String etiqueta;
  final String? ayuda;
  final String? valorInicial;
  final String? textoInicial;
  final bool habilitado;
  final bool requerido;
  final ValueChanged<String?> alCambiar;

  @override
  State<CampoReferencia> createState() => _CampoReferenciaState();
}

class _CampoReferenciaState extends State<CampoReferencia> {
  String? _valor;
  String? _etiquetaElegida;
  String? _errorBusqueda;

  @override
  void initState() {
    super.initState();
    _valor = widget.valorInicial;
    _etiquetaElegida = widget.textoInicial;
  }

  Future<Iterable<Opcion>> _buscar(TextEditingValue texto) async {
    // Mientras el texto sea la opción ya elegida, se muestran las primeras.
    final q = texto.text == _etiquetaElegida ? '' : texto.text;
    try {
      final opciones = await widget.api.opciones(widget.referencia, q);
      if (_errorBusqueda != null) setState(() => _errorBusqueda = null);
      return opciones;
    } on ErrorApi catch (e) {
      setState(() => _errorBusqueda = e.mensaje);
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Opcion>(
      initialValue: TextEditingValue(text: widget.textoInicial ?? ''),
      displayStringForOption: (o) => o.etiqueta,
      optionsBuilder: _buscar,
      onSelected: (o) {
        _valor = o.valor;
        _etiquetaElegida = o.etiqueta;
        widget.alCambiar(o.valor);
      },
      optionsViewBuilder: (context, alElegir, opciones) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in opciones)
                  ListTile(dense: true, title: Text(o.etiqueta), onTap: () => alElegir(o)),
              ],
            ),
          ),
        ),
      ),
      fieldViewBuilder: (context, controlador, foco, alEnviar) => TextFormField(
        controller: controlador,
        focusNode: foco,
        enabled: widget.habilitado,
        decoration: InputDecoration(
          labelText: widget.etiqueta,
          helperText: _errorBusqueda ?? widget.ayuda ?? 'Escribe para buscar',
          helperMaxLines: 3,
          suffixIcon: const Icon(Icons.search, size: 20),
        ),
        onChanged: (texto) {
          if (texto != _etiquetaElegida && _valor != null) {
            _valor = null;
            widget.alCambiar(null);
          }
        },
        validator: (_) => widget.requerido && _valor == null ? 'Elige una opción de la lista' : null,
      ),
    );
  }
}
