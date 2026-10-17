import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// Exige sesión iniciada y una empresa válida para el usuario.
/// Deja disponible la [Sesion] para las rutas que siguen.
Middleware requiereSesion() {
  return (handler) {
    return (context) async {
      try {
        final sesion = await context.read<Dependencias>().auth.validar(
              context.request.headers['authorization'],
              context.request.headers['x-empresa-id'],
            );
        return await handler(context.provide<Sesion>(() => sesion));
      } on ErrorAcceso catch (e) {
        return respuestaError(e.estado, e.mensaje);
      }
    };
  };
}

/// Exige que el usuario tenga al menos uno de [roles] en la empresa activa.
Middleware requiereRol(Set<String> roles) {
  return (handler) {
    return (context) {
      final sesion = context.read<Sesion>();
      if (!sesion.accesos.any((a) => roles.contains(a.rol))) {
        return respuestaError(403, 'Esta sección es solo para: ${roles.map((r) => r.toLowerCase()).join(', ')}.');
      }
      return handler(context);
    };
  };
}
