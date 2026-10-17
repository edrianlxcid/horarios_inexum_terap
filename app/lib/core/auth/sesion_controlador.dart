import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/cliente_api.dart';
import 'modelos_sesion.dart';

enum EstadoSesion { cargando, sinSesion, elegirEmpresa, activa }

/// Estado de la sesión de toda la app: tokens, empresa activa y rol activo.
///
/// El token de acceso vive solo en memoria; el de renovación se guarda en el
/// almacenamiento seguro del dispositivo para no pedir la contraseña cada vez.
class SesionControlador extends ChangeNotifier implements ProveedorSesion {
  SesionControlador(this._api, {FlutterSecureStorage? almacen}) : _almacen = almacen ?? const FlutterSecureStorage() {
    _api.sesion = this;
  }

  final ClienteApi _api;
  final FlutterSecureStorage _almacen;
  static const _claveRenovacion = 'ismart.token_renovacion';
  static const _claveEmpresa = 'ismart.empresa';

  EstadoSesion estado = EstadoSesion.cargando;
  List<EmpresaAcceso> empresas = const [];
  EmpresaAcceso? empresa;
  String? rol;
  Map<String, dynamic>? usuario;

  String? _acceso;
  String? _renovacion;
  Future<bool>? _renovando;

  @override
  String? get tokenAcceso => _acceso;

  @override
  String? get empresaId => empresa?.id;

  String get nombreUsuario => usuario == null ? '' : '${usuario!['nombres']} ${usuario!['apellidos']}';

  /// Al abrir la app: si hay un token de renovación guardado, recupera la sesión.
  Future<void> iniciar() async {
    try {
      _renovacion = await _almacen.read(key: _claveRenovacion);
    } on Exception {
      _renovacion = null;
    }
    if (_renovacion == null || !await renovar()) {
      _cambiar(EstadoSesion.sinSesion);
    }
  }

  Future<void> ingresar(String email, String password) async {
    final datos = await _api.post<Map<String, dynamic>>(
      '/api/auth/login',
      {'email': email, 'password': password},
      publica: true,
    );
    await _aplicar(datos);
  }

  /// Solo en desarrollo: entra como un usuario de prueba sin contraseña.
  Future<void> accesoRapido(String usuarioId) async {
    final datos = await _api.post<Map<String, dynamic>>('/api/dev/accesos', {'usuario_id': usuarioId}, publica: true);
    await _aplicar(datos);
  }

  @override
  Future<bool> renovar() {
    // Si varias peticiones vencen a la vez, se renueva una sola vez.
    return _renovando ??= _renovarUnaVez().whenComplete(() => _renovando = null);
  }

  Future<bool> _renovarUnaVez() async {
    final token = _renovacion;
    if (token == null) return false;
    try {
      final datos = await _api.post<Map<String, dynamic>>(
        '/api/auth/renovar',
        {'token_renovacion': token},
        publica: true,
      );
      await _aplicar(datos, conservarEmpresa: true);
      return true;
    } on ErrorApi {
      await _limpiar();
      return false;
    }
  }

  Future<void> _aplicar(Map<String, dynamic> datos, {bool conservarEmpresa = false}) async {
    _acceso = datos['token_acceso'] as String;
    _renovacion = datos['token_renovacion'] as String;
    await _guardar(_claveRenovacion, _renovacion);
    empresas = [for (final e in datos['empresas'] as List) EmpresaAcceso.fromJson(e as Map<String, dynamic>)];

    final anterior = conservarEmpresa ? (empresa?.id ?? await _leer(_claveEmpresa)) : null;
    final elegida = empresas.where((e) => e.id == anterior).firstOrNull ?? (empresas.length == 1 ? empresas.first : null);
    if (elegida == null) {
      empresa = null;
      _cambiar(EstadoSesion.elegirEmpresa);
    } else {
      await elegirEmpresa(elegida, rolPreferido: rol);
    }
  }

  Future<void> elegirEmpresa(EmpresaAcceso e, {String? rolPreferido}) async {
    empresa = e;
    rol = e.rolesDistintos.contains(rolPreferido) ? rolPreferido : e.rolesDistintos.first;
    await _guardar(_claveEmpresa, e.id);
    try {
      final yo = await _api.get<Map<String, dynamic>>('/api/v1/yo');
      usuario = yo['usuario'] as Map<String, dynamic>?;
    } on ErrorApi {
      usuario = null;
    }
    _cambiar(EstadoSesion.activa);
  }

  void elegirRol(String nuevo) {
    rol = nuevo;
    notifyListeners();
  }

  /// Vuelve a la pantalla de elegir empresa (para quien tiene varias).
  void cambiarEmpresa() => _cambiar(EstadoSesion.elegirEmpresa);

  Future<void> salir() async {
    final token = _renovacion;
    if (token != null) {
      try {
        await _api.post<dynamic>('/api/auth/salir', {'token_renovacion': token}, publica: true);
      } on ErrorApi {
        // Aunque la API no responda, la sesión local se cierra igual.
      }
    }
    await _limpiar();
  }

  Future<void> _limpiar() async {
    _acceso = null;
    _renovacion = null;
    empresas = const [];
    empresa = null;
    rol = null;
    usuario = null;
    await _guardar(_claveRenovacion, null);
    _cambiar(EstadoSesion.sinSesion);
  }

  void _cambiar(EstadoSesion nuevo) {
    estado = nuevo;
    notifyListeners();
  }

  Future<void> _guardar(String clave, String? valor) async {
    try {
      if (valor == null) {
        await _almacen.delete(key: clave);
      } else {
        await _almacen.write(key: clave, value: valor);
      }
    } on Exception catch (e) {
      debugPrint('No se pudo usar el almacenamiento seguro: $e');
    }
  }

  Future<String?> _leer(String clave) async {
    try {
      return await _almacen.read(key: clave);
    } on Exception {
      return null;
    }
  }
}
