import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/modelos_sesion.dart';
import '../../../core/dependencias.dart';
import '../../../core/network/cliente_api.dart';
import '../../herramienta_datos/presentation/pagina_datos.dart';

/// Inicio de sesión. En desarrollo muestra además un acceso rápido con
/// usuarios de prueba de cada empresa y rol, para probar cada interfaz.
class PaginaLogin extends StatefulWidget {
  const PaginaLogin({super.key});

  @override
  State<PaginaLogin> createState() => _PaginaLoginState();
}

class _PaginaLoginState extends State<PaginaLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = Dependencias.de(context).sesion;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('iSmart · Horarios', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  onSubmitted: (_) => _entrar(() => sesion.ingresar(_email.text.trim(), _password.text)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _cargando ? null : () => _entrar(() => sesion.ingresar(_email.text.trim(), _password.text)),
                  child: _cargando ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Ingresar'),
                ),
                if (kDebugMode || const bool.fromEnvironment('MOSTRAR_DESARROLLO', defaultValue: true))
                  _AccesoRapido(alElegir: (id) => _entrar(() => sesion.accesoRapido(id))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lista de usuarios de prueba por empresa y rol (solo existe en desarrollo).
class _AccesoRapido extends StatelessWidget {
  const _AccesoRapido({required this.alElegir});

  final ValueChanged<String> alElegir;

  @override
  Widget build(BuildContext context) {
    final cliente = Dependencias.de(context).cliente;
    return FutureBuilder<List<dynamic>>(
      future: cliente.get<List<dynamic>>('/api/dev/accesos', publica: true),
      builder: (context, s) {
        if (!s.hasData) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 40),
            Text('Acceso rápido de desarrollo', style: Theme.of(context).textTheme.titleSmall),
            const Text('Entra como un usuario de prueba para revisar cada interfaz.'),
            for (final e in s.data!.cast<Map<String, dynamic>>())
              ExpansionTile(
                title: Text(e['empresa'] as String),
                subtitle: Text(e['rubro'] as String),
                children: [
                  for (final u in (e['usuarios'] as List).cast<Map<String, dynamic>>())
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.login),
                      title: Text('${nombresRoles[u['rol']] ?? u['rol']} · ${u['nombre']}'),
                      subtitle: Text([u['email'], if ((u['alcance'] as String).isNotEmpty) u['alcance']].join(' · ')),
                      onTap: () => alElegir(u['usuario_id'] as String),
                    ),
                ],
              ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PaginaDatos(api: Dependencias.de(context).datosDesarrollo),
              )),
              icon: const Icon(Icons.dataset_outlined),
              label: const Text('Herramienta de datos (todas las tablas)'),
            ),
          ],
        );
      },
    );
  }
}
