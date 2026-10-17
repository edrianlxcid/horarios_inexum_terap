/// Nombre visible de cada rol.
const nombresRoles = {
  'GERENCIA': 'Gerencia',
  'ADMINISTRADOR': 'Administración',
  'COORDINADOR': 'Coordinación',
  'TERAPEUTA': 'Terapeuta',
  'REPRESENTANTE': 'Familias',
};

/// Un rol del usuario en una empresa, con su alcance (sede y área).
class RolAcceso {
  const RolAcceso({required this.rol, required this.nivel, this.sedeId, this.sede, this.areaId, this.area});

  factory RolAcceso.fromJson(Map<String, dynamic> j) => RolAcceso(
        rol: j['rol'] as String,
        nivel: j['nivel'] as int,
        sedeId: j['sede_id'] as String?,
        sede: j['sede'] as String?,
        areaId: j['area_id'] as String?,
        area: j['area'] as String?,
      );

  final String rol;
  final int nivel;
  final String? sedeId;
  final String? sede;
  final String? areaId;
  final String? area;

  String get alcance => [sede ?? 'Todas las sedes', area ?? 'todas las áreas'].join(' · ');
}

/// Empresa (matriz o sucursal) a la que el usuario tiene acceso.
class EmpresaAcceso {
  const EmpresaAcceso({
    required this.id,
    required this.nombre,
    required this.rubro,
    required this.roles,
    required this.permisos,
    this.color,
  });

  factory EmpresaAcceso.fromJson(Map<String, dynamic> j) => EmpresaAcceso(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        rubro: j['rubro'] as String,
        color: j['color'] as String?,
        roles: [for (final r in j['roles'] as List) RolAcceso.fromJson(r as Map<String, dynamic>)],
        permisos: (j['permisos'] as List).cast<String>(),
      );

  final String id;
  final String nombre;
  final String rubro;
  final String? color;
  final List<RolAcceso> roles;
  final List<String> permisos;

  /// Roles distintos, del de mayor nivel al de menor.
  List<String> get rolesDistintos {
    final ordenados = [...roles]..sort((a, b) => b.nivel.compareTo(a.nivel));
    return ordenados.map((r) => r.rol).toSet().toList();
  }

  List<RolAcceso> alcanceDe(String rol) => roles.where((r) => r.rol == rol).toList();
}
