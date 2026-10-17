import 'package:backend/core/http/guardias.dart';
import 'package:dart_frog/dart_frog.dart';

/// Solo para usuarios con rol ADMINISTRADOR en la empresa activa.
Handler middleware(Handler handler) => handler.use(requiereRol({'ADMINISTRADOR'}));
