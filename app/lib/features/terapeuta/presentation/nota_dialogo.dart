import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';
import '../../../core/util/formatos.dart';
import '../../../core/widgets/comunes.dart';
import '../domain/modelos.dart';

/// Abre la nota de la sesión. Devuelve true si se guardó algo.
Future<bool?> mostrarNotaDialogo(BuildContext context, String participanteId) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: _NotaDialogo(participanteId: participanteId),
      ),
    ),
  );
}

class _NotaDialogo extends StatelessWidget {
  const _NotaDialogo({required this.participanteId});

  final String participanteId;

  @override
  Widget build(BuildContext context) {
    final api = Dependencias.de(context).terapeuta;
    return Cargador<NotaSesion>(
      cargar: () => api.nota(participanteId),
      construir: (context, nota, _) => _FormularioNota(nota: nota),
    );
  }
}

class _FormularioNota extends StatefulWidget {
  const _FormularioNota({required this.nota});

  final NotaSesion nota;

  @override
  State<_FormularioNota> createState() => _FormularioNotaState();
}

class _FormularioNotaState extends State<_FormularioNota> {
  late final _contenido = TextEditingController(text: widget.nota.contenido);
  late final _resumen = TextEditingController(text: widget.nota.resumenFamilia);
  final _avances = <String, int>{};
  bool _guardando = false;

  @override
  void dispose() {
    _contenido.dispose();
    _resumen.dispose();
    super.dispose();
  }

  Future<void> _guardar({required bool firmar}) async {
    if (_contenido.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe la nota antes de guardar.')));
      return;
    }
    if (firmar) {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Firmar la nota?'),
          content: const Text('Una nota firmada ya no se puede editar. Las correcciones se agregan como anexo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Firmar')),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;
    }
    setState(() => _guardando = true);
    final api = Dependencias.de(context).terapeuta;
    final ok = await ejecutarConAviso(
      context,
      () => api.guardarNota(
        widget.nota.participanteId,
        contenido: _contenido.text.trim(),
        resumenFamilia: _resumen.text.trim().isEmpty ? null : _resumen.text.trim(),
        firmar: firmar,
        avances: _avances,
      ),
      exito: firmar ? 'Nota firmada' : 'Borrador guardado',
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.nota;
    final soloLectura = n.firmada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text('Nota · ${n.paciente}'),
          subtitle: Text([Formatos.fechaHora(n.inicio), ?n.programa, if (n.numeroSesion != null) 'sesión ${n.numeroSesion}'].join(' · ')),
          trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (soloLectura)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Etiqueta('Firmada el ${n.firmadaEn}', tono: Tono.bien),
                ),
              TextField(
                controller: _contenido,
                readOnly: soloLectura,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Nota clínica (solo la ve el equipo, se guarda cifrada)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _resumen,
                readOnly: soloLectura,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Resumen para la familia (opcional)'),
              ),
              if (n.objetivos.isNotEmpty && !soloLectura) ...[
                const TituloSeccion('Avance de objetivos (opcional)'),
                for (final o in n.objetivos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('${o.descripcion}${o.ultimoNivel != null ? '  (último: ${o.ultimoNivel})' : ''}')),
                        DropdownButton<int?>(
                          value: _avances[o.id],
                          hint: const Text('Nivel'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('—')),
                            for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i')),
                          ],
                          onChanged: (v) => setState(() => v == null ? _avances.remove(o.id) : _avances[o.id] = v),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (!soloLectura)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton(onPressed: _guardando ? null : () => _guardar(firmar: false), child: const Text('Guardar borrador')),
                FilledButton(onPressed: _guardando ? null : () => _guardar(firmar: true), child: const Text('Firmar nota')),
              ],
            ),
          ),
      ],
    );
  }
}
