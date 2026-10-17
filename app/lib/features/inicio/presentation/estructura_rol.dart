import 'package:flutter/material.dart';

import '../../../core/auth/modelos_sesion.dart';
import '../../../core/dependencias.dart';
import '../../administracion/presentation/pagina_administracion.dart';
import '../../coordinacion/presentation/pagina_coordinacion.dart';
import '../../familias/presentation/pagina_familias.dart';
import '../../gerencia/presentation/pagina_gerencia.dart';
import '../../terapeuta/presentation/pagina_terapeuta.dart';

/// Estructura común después de iniciar sesión: barra con la empresa, el rol
/// activo (si tiene varios, puede cambiarlo) y el cierre de sesión.
/// El contenido depende del rol activo.
class EstructuraRol extends StatelessWidget {
  const EstructuraRol({super.key});

  static Widget _paginaDe(String rol) => switch (rol) {
        'GERENCIA' => const PaginaGerencia(),
        'ADMINISTRADOR' => const PaginaAdministracion(),
        'COORDINADOR' => const PaginaCoordinacion(),
        'TERAPEUTA' => const PaginaTerapeuta(),
        'REPRESENTANTE' => const PaginaFamilias(),
        _ => Center(child: Text('El rol $rol todavía no tiene pantalla.')),
      };

  @override
  Widget build(BuildContext context) {
    final sesion = Dependencias.de(context).sesion;
    final empresa = sesion.empresa!;
    final rol = sesion.rol!;
    final roles = empresa.rolesDistintos;
    final alcance = empresa.alcanceDe(rol).map((a) => a.alcance).toSet().join(' | ');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nombresRoles[rol] ?? rol),
            Text('${empresa.nombre} · $alcance', style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (roles.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Cambiar de rol',
              icon: const Icon(Icons.switch_account),
              onSelected: sesion.elegirRol,
              itemBuilder: (_) => [for (final r in roles) CheckedPopupMenuItem(value: r, checked: r == rol, child: Text(nombresRoles[r] ?? r))],
            ),
          if (sesion.empresas.length > 1)
            IconButton(tooltip: 'Cambiar de empresa', onPressed: sesion.cambiarEmpresa, icon: const Icon(Icons.business)),
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            icon: const Icon(Icons.account_circle),
            onSelected: (_) => sesion.salir(),
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(sesion.nombreUsuario)),
              const PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: KeyedSubtree(key: ValueKey('${empresa.id}$rol'), child: _paginaDe(rol)),
    );
  }
}
