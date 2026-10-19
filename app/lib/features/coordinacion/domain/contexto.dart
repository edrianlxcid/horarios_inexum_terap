/// Lista de objetos JSON (vacía si no viene).
List<Map<String, dynamic>> listaJson(Object? v) => ((v as List?) ?? const []).cast<Map<String, dynamic>>();

class Opcion {
  const Opcion(this.id, this.nombre, {this.extra = const {}});

  factory Opcion.fromJson(Map<String, dynamic> j) => Opcion(j['id'] as String, j['nombre'] as String, extra: j);

  final String id;
  final String nombre;
  final Map<String, dynamic> extra;

  String? get areaId => extra['area_id'] as String?;
}

/// Lo que el coordinador puede ver: sedes, áreas, especialidades, terapeutas
/// y programas de su alcance, y si puede registrar profesionales.
class ContextoCoordinacion {
  const ContextoCoordinacion({
    required this.sedes,
    required this.areas,
    required this.especialidades,
    required this.terapeutas,
    required this.programas,
    required this.nivelesDemanda,
    required this.puedeRegistrarProfesionales,
  });

  factory ContextoCoordinacion.fromJson(Map<String, dynamic> j) {
    List<Opcion> opciones(String k) => [for (final x in listaJson(j[k])) Opcion.fromJson(x)];
    return ContextoCoordinacion(
      sedes: opciones('sedes'),
      areas: opciones('areas'),
      especialidades: opciones('especialidades'),
      terapeutas: opciones('terapeutas'),
      programas: opciones('programas'),
      nivelesDemanda: opciones('niveles_demanda'),
      puedeRegistrarProfesionales: j['puede_registrar_profesionales'] == true,
    );
  }

  final List<Opcion> sedes, areas, especialidades, terapeutas, programas, nivelesDemanda;
  final bool puedeRegistrarProfesionales;

  List<Opcion> terapeutasDeArea(String? areaId) => areaId == null
      ? terapeutas
      : terapeutas.where((t) => (t.extra['areas'] as List).contains(areaId)).toList();

  /// Quienes hacen valoraciones, de cualquier área: también se valora (como
  /// excepción) a estudiantes de Estimulación temprana.
  List<Opcion> get terapeutasQueValoran => terapeutas.where((t) => t.extra['valora'] == true).toList();

  List<Opcion> especialidadesDeArea(String? areaId) =>
      areaId == null ? especialidades : especialidades.where((e) => e.areaId == areaId).toList();

  List<Opcion> programasDeArea(String? areaId) =>
      areaId == null ? programas : programas.where((p) => p.areaId == areaId).toList();
}
