import 'package:flutter/material.dart';

import '../../../core/dependencias.dart';

/// Para usuarios que pertenecen a varias empresas (por ejemplo, gerencia de la
/// matriz que también ve una sucursal): elige con cuál trabajar.
class PaginaElegirEmpresa extends StatelessWidget {
  const PaginaElegirEmpresa({super.key});

  @override
  Widget build(BuildContext context) {
    final sesion = Dependencias.de(context).sesion;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige la empresa'),
        actions: [TextButton(onPressed: sesion.salir, child: const Text('Salir'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              for (final e in sesion.empresas)
                Card(
                  child: ListTile(
                    title: Text(e.nombre),
                    subtitle: Text('${e.rubro}\nTus roles: ${e.rolesDistintos.join(', ').toLowerCase()}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => sesion.elegirEmpresa(e),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
