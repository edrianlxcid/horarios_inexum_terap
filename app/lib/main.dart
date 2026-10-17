import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/auth/sesion_controlador.dart';
import 'core/dependencias.dart';
import 'core/network/cliente_api.dart';
import 'core/theme/tema.dart';
import 'features/auth/presentation/pagina_elegir_empresa.dart';
import 'features/auth/presentation/pagina_login.dart';
import 'features/inicio/presentation/estructura_rol.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  runApp(Dependencias(cliente: ClienteApi(), child: const AppIsmart()));
}

class AppIsmart extends StatefulWidget {
  const AppIsmart({super.key});

  @override
  State<AppIsmart> createState() => _AppIsmartState();
}

class _AppIsmartState extends State<AppIsmart> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Dependencias.de(context).sesion.iniciar());
  }

  @override
  Widget build(BuildContext context) {
    final sesion = Dependencias.de(context).sesion;
    return MaterialApp(
      title: 'iSmart · Horarios',
      debugShowCheckedModeBanner: false,
      theme: TemaApp.claro(),
      darkTheme: TemaApp.oscuro(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // La pantalla depende del estado de la sesión: sin sesión → login;
      // varias empresas → elegir; sesión activa → la interfaz del rol.
      home: ListenableBuilder(
        listenable: sesion,
        builder: (context, _) => switch (sesion.estado) {
          EstadoSesion.cargando => const Scaffold(body: Center(child: CircularProgressIndicator())),
          EstadoSesion.sinSesion => const PaginaLogin(),
          EstadoSesion.elegirEmpresa => const PaginaElegirEmpresa(),
          EstadoSesion.activa => const EstructuraRol(),
        },
      ),
    );
  }
}
