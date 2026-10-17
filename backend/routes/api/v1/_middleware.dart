import 'package:backend/core/http/guardias.dart';
import 'package:dart_frog/dart_frog.dart';

/// Todo lo que está bajo /api/v1 exige sesión iniciada y empresa válida
/// (cabecera X-Empresa-Id cuando el usuario pertenece a varias).
Handler middleware(Handler handler) => handler.use(requiereSesion());
