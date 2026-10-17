/// Un rol asignado a un usuario dentro de una empresa, con su alcance.
class Acceso {
  Acceso({
    required this.rol,
    required this.nivel,
    required this.permisos,
    this.sedeId,
    this.sede,
    this.areaId,
    this.area,
  });

  final String rol;
  final int nivel;
  final String? sedeId;
  final String? sede;
  final String? areaId;
  final String? area;
  final List<String> permisos;

  Map<String, Object?> toJson() => {
        'rol': rol,
        'nivel': nivel,
        'sede_id': sedeId,
        'sede': sede,
        'area_id': areaId,
        'area': area,
      };
}

/// Empresa a la que el usuario tiene acceso, con sus roles en ella.
class EmpresaAcceso {
  EmpresaAcceso({
    required this.id,
    required this.nombre,
    required this.codigo,
    required this.rubro,
    required this.color,
    required this.accesos,
  });

  final String id;
  final String nombre;
  final String codigo;
  final String rubro;
  final String? color;
  final List<Acceso> accesos;

  Map<String, Object?> toJson() => {
        'id': id,
        'nombre': nombre,
        'codigo': codigo,
        'rubro': rubro,
        'color': color,
        'roles': [for (final a in accesos) a.toJson()],
        'permisos': {for (final a in accesos) ...a.permisos}.toList()..sort(),
      };
}

/// Quién hace la petición y en qué empresa está trabajando.
/// La arma el middleware de /api/v1 a partir del token y de X-Empresa-Id.
class Sesion {
  Sesion({required this.usuarioId, required this.empresa});

  final String usuarioId;
  final EmpresaAcceso empresa;

  String get empresaId => empresa.id;
  List<Acceso> get accesos => empresa.accesos;

  bool tieneRol(String rol) => accesos.any((a) => a.rol == rol);

  bool puede(String permiso) => accesos.any((a) => a.permisos.contains(permiso));

  /// Pares (sede, área) en los que el usuario tiene el rol. Un valor nulo
  /// significa "todas". Sirve para filtrar consultas por alcance.
  List<Map<String, String?>> alcance(String rol) => [
        for (final a in accesos.where((a) => a.rol == rol)) {'sede': a.sedeId, 'area': a.areaId},
      ];
}

/// Falta de autenticación (401) o de permisos (403).
class ErrorAcceso implements Exception {
  ErrorAcceso(this.estado, this.mensaje);

  final int estado;
  final String mensaje;

  @override
  String toString() => mensaje;
}
