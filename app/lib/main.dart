import 'package:flutter/material.dart';

import 'core/network/cliente_api.dart';
import 'core/theme/tema.dart';
import 'features/herramienta_datos/data/datos_api.dart';
import 'features/herramienta_datos/presentation/pagina_datos.dart';

void main() {
  runApp(AppIsmart(datosApi: DatosApi(ClienteApi())));
}

class AppIsmart extends StatelessWidget {
  const AppIsmart({super.key, required this.datosApi});

  final DatosApi datosApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Datos iSmart',
      debugShowCheckedModeBanner: false,
      theme: TemaApp.claro(),
      darkTheme: TemaApp.oscuro(),
      home: PaginaDatos(api: datosApi),
    );
  }
}
