import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:postgres/postgres.dart';

/// Consultas del inicio de sesión. Las que corren antes de conocer la empresa
/// usan funciones de la base con permisos del dueño (seguridad.credenciales,
/// seguridad.accesos), porque el aislamiento por empresa aún no aplica.
class AuthRepositorio {
  Future<Map<String, dynamic>?> credenciales(Session db, String email) => fila(
        db,
        'SELECT usuario_id::text, password_hash, activo, bloqueado_hasta > now() AS bloqueado '
        'FROM seguridad.credenciales(@email:text)',
        {'email': email},
      );

  Future<bool> passwordCorrecta(Session db, String password, String hash) async {
    final r = await fila(db, 'SELECT crypt(@p:text, @h:text) = @h:text AS ok', {'p': password, 'h': hash});
    return r!['ok'] as bool;
  }

  Future<void> registrarIntento(Session db, String usuarioId, {required bool exitoso}) => consultar(
        db,
        'SELECT seguridad.registrar_intento(CAST(@u:text AS uuid), @ok:boolean)',
        {'u': usuarioId, 'ok': exitoso},
      );

  Future<List<EmpresaAcceso>> accesos(Session db, String usuarioId) async {
    final rs = await filas(
      db,
      'SELECT empresa_id::text, empresa, empresa_codigo, rubro, color_marca, rol, nivel, '
      'sede_id::text, sede, area_id::text, area, permisos '
      'FROM seguridad.accesos(CAST(@u:text AS uuid))',
      {'u': usuarioId},
    );
    final porEmpresa = <String, EmpresaAcceso>{};
    for (final r in rs) {
      final empresa = porEmpresa.putIfAbsent(
        r['empresa_id'] as String,
        () => EmpresaAcceso(
          id: r['empresa_id'] as String,
          nombre: r['empresa'] as String,
          codigo: r['empresa_codigo'] as String,
          rubro: r['rubro'] as String,
          color: r['color_marca'] as String?,
          accesos: [],
        ),
      );
      empresa.accesos.add(
        Acceso(
          rol: r['rol'] as String,
          nivel: r['nivel'] as int,
          sedeId: r['sede_id'] as String?,
          sede: r['sede'] as String?,
          areaId: r['area_id'] as String?,
          area: r['area'] as String?,
          permisos: (r['permisos'] as List).cast<String>(),
        ),
      );
    }
    return porEmpresa.values.toList();
  }

  Future<void> guardarRenovacion(
    Session db, {
    required String usuarioId,
    required String hash,
    required String app,
    required Duration duracion,
    String? dispositivo,
  }) =>
      consultar(
        db,
        'INSERT INTO seguridad.sesiones_usuario (usuario_id, refresh_token_hash, app, dispositivo, expira_en) '
        "VALUES (CAST(@u:text AS uuid), @h:text, @a:text, @d:text, now() + CAST(@s:text || ' seconds' AS interval))",
        {'u': usuarioId, 'h': hash, 'a': app, 'd': dispositivo, 's': duracion.inSeconds.toString()},
      );

  /// Revoca el token de renovación y devuelve su usuario, si seguía vigente.
  Future<Map<String, dynamic>?> consumirRenovacion(Session db, String hash) => fila(
        db,
        'UPDATE seguridad.sesiones_usuario SET revocado_en = now() '
        'WHERE refresh_token_hash = @h:text AND revocado_en IS NULL AND expira_en > now() '
        'RETURNING usuario_id::text, app',
        {'h': hash},
      );

  /// Datos personales y vínculos del usuario dentro de la empresa activa.
  Future<Map<String, dynamic>?> perfil(Session db, String usuarioId) => fila(
        db,
        '''
        SELECT u.id::text, u.email, u.nombres, u.apellidos,
               (SELECT p.id::text FROM personas.profesionales p WHERE p.usuario_id = u.id) AS profesional_id,
               (SELECT r.id::text FROM personas.representantes r WHERE r.usuario_id = u.id) AS representante_id
        FROM seguridad.usuarios u WHERE u.id = CAST(@u:text AS uuid)''',
        {'u': usuarioId},
      );
}
