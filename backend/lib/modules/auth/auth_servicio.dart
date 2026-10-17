import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/auth/tokens.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/auth/auth_repositorio.dart';
import 'package:postgres/postgres.dart';

/// Inicio de sesión, renovación y validación de a qué empresa pertenece el usuario.
class AuthServicio {
  AuthServicio(this._db, this._repo, this._tokens);

  final BaseDatos _db;
  final AuthRepositorio _repo;
  final Tokens _tokens;

  /// Accesos en memoria por un minuto, para no consultarlos en cada petición.
  final _cache = <String, (DateTime, List<EmpresaAcceso>)>{};

  Future<Map<String, Object?>> iniciarSesion(String email, String password, {String? dispositivo}) async {
    // Mismo mensaje si el correo no existe o la contraseña falla: no revela qué cuentas existen.
    const invalido = 'Correo o contraseña incorrectos.';
    final cred = await _db.sinEmpresa((tx) => _repo.credenciales(tx, email.trim()));
    if (cred == null) throw ErrorAcceso(401, invalido);
    final usuarioId = cred['usuario_id'] as String;
    if (cred['activo'] != true) throw ErrorAcceso(403, 'La cuenta está desactivada.');
    if (cred['bloqueado'] == true) {
      throw ErrorAcceso(403, 'La cuenta está bloqueada por varios intentos fallidos. Intenta en 15 minutos.');
    }
    // El intento se guarda en su propia transacción para que quede aunque falle.
    final ok = await _db.sinEmpresa((tx) async {
      final correcta = await _repo.passwordCorrecta(tx, password, cred['password_hash'] as String);
      await _repo.registrarIntento(tx, usuarioId, exitoso: correcta);
      return correcta;
    });
    if (!ok) throw ErrorAcceso(401, invalido);
    return _db.sinEmpresa((tx) => _emitir(tx, usuarioId, dispositivo: dispositivo));
  }

  /// Entrega una sesión nueva a partir de un token de renovación (y lo invalida).
  Future<Map<String, Object?>> renovar(String renovacion) {
    return _db.sinEmpresa((tx) async {
      final r = await _repo.consumirRenovacion(tx, Tokens.hash(renovacion));
      if (r == null) throw ErrorAcceso(401, 'La sesión expiró. Vuelve a iniciar sesión.');
      return _emitir(tx, r['usuario_id'] as String);
    });
  }

  Future<void> cerrarSesion(String renovacion) =>
      _db.sinEmpresa((tx) => _repo.consumirRenovacion(tx, Tokens.hash(renovacion)));

  /// Solo para la herramienta de desarrollo: sesión sin contraseña.
  Future<Map<String, Object?>> sesionDeDesarrollo(String usuarioId) =>
      _db.sinEmpresa((tx) => _emitir(tx, usuarioId, dispositivo: 'acceso rápido de desarrollo'));

  Future<Map<String, Object?>> _emitir(Session tx, String usuarioId, {String? dispositivo}) async {
    final empresas = await _repo.accesos(tx, usuarioId);
    if (empresas.isEmpty) throw ErrorAcceso(403, 'Tu usuario no tiene acceso a ninguna empresa.');
    final soloFamilia = empresas.every((e) => e.accesos.every((a) => a.rol == 'REPRESENTANTE'));
    final renovacion = Tokens.crearRenovacion();
    await _repo.guardarRenovacion(
      tx,
      usuarioId: usuarioId,
      hash: Tokens.hash(renovacion),
      app: soloFamilia ? 'FAMILIAS' : 'EQUIPO',
      duracion: Tokens.duracionRenovacion,
      dispositivo: dispositivo,
    );
    _cache[usuarioId] = (DateTime.now(), empresas);
    return {
      'token_acceso': _tokens.crearAcceso(usuarioId),
      'token_renovacion': renovacion,
      'expira_en_segundos': Tokens.duracionAcceso.inSeconds,
      'empresas': [for (final e in empresas) e.toJson()],
    };
  }

  /// Valida el token y la empresa elegida, y arma la sesión de la petición.
  Future<Sesion> validar(String? autorizacion, String? empresaId) async {
    if (autorizacion == null || !autorizacion.startsWith('Bearer ')) {
      throw ErrorAcceso(401, 'Inicia sesión para continuar.');
    }
    final usuarioId = _tokens.verificarAcceso(autorizacion.substring(7));
    if (usuarioId == null) throw ErrorAcceso(401, 'La sesión expiró. Vuelve a iniciar sesión.');

    final empresas = await _accesos(usuarioId);
    if (empresas.isEmpty) throw ErrorAcceso(403, 'Tu usuario ya no tiene acceso a ninguna empresa.');
    final EmpresaAcceso empresa;
    if (empresaId == null || empresaId.isEmpty) {
      if (empresas.length > 1) throw ErrorAcceso(400, 'Elige con qué empresa quieres trabajar.');
      empresa = empresas.first;
    } else {
      final elegida = empresas.where((e) => e.id == empresaId);
      if (elegida.isEmpty) throw ErrorAcceso(403, 'No perteneces a la empresa indicada.');
      empresa = elegida.first;
    }
    return Sesion(usuarioId: usuarioId, empresa: empresa);
  }

  Future<List<EmpresaAcceso>> _accesos(String usuarioId) async {
    final guardado = _cache[usuarioId];
    if (guardado != null && DateTime.now().difference(guardado.$1) < const Duration(minutes: 1)) {
      return guardado.$2;
    }
    final empresas = await _db.sinEmpresa((tx) => _repo.accesos(tx, usuarioId));
    _cache[usuarioId] = (DateTime.now(), empresas);
    return empresas;
  }

  Future<Map<String, Object?>> perfil(Sesion sesion) async {
    final datos = await _db.conSesion(sesion, (tx) => _repo.perfil(tx, sesion.usuarioId));
    return {
      'usuario': datos,
      'empresa': sesion.empresa.toJson(),
      'empresas': [for (final e in await _accesos(sesion.usuarioId)) e.toJson()],
    };
  }
}
