import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Tokens de sesión:
/// - acceso: JWT firmado que dura 15 minutos y solo dice quién es el usuario.
/// - renovación: valor aleatorio que dura 30 días; en la base solo se guarda su hash.
class Tokens {
  Tokens(this._secreto);

  final String _secreto;

  static const duracionAcceso = Duration(minutes: 15);
  static const duracionRenovacion = Duration(days: 30);

  String crearAcceso(String usuarioId) {
    final jwt = JWT({'tipo': 'acceso'}, subject: usuarioId, issuer: 'ismart-horarios');
    return jwt.sign(SecretKey(_secreto), expiresIn: duracionAcceso);
  }

  /// Devuelve el id del usuario, o null si el token no es válido o venció.
  String? verificarAcceso(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secreto), issuer: 'ismart-horarios');
      final datos = jwt.payload;
      if (datos is! Map || datos['tipo'] != 'acceso') return null;
      return jwt.subject;
    } on JWTException {
      return null;
    }
  }

  static String crearRenovacion() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static String hash(String valor) => sha256.convert(utf8.encode(valor)).toString();
}
