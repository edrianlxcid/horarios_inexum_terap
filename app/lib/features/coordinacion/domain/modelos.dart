List<Map<String, dynamic>> _lista(Object? v) => (v as List).cast<Map<String, dynamic>>();

class Opcion {
  const Opcion(this.id, this.nombre, {this.extra = const {}});

  factory Opcion.fromJson(Map<String, dynamic> j) =>
      Opcion(j['id'] as String, j['nombre'] as String, extra: j);

  final String id;
  final String nombre;
  final Map<String, dynamic> extra;
}

/// Lo que el coordinador puede ver: sedes, áreas, terapeutas y programas de su alcance.
class ContextoCoordinacion {
  const ContextoCoordinacion({
    required this.sedes,
    required this.areas,
    required this.terapeutas,
    required this.programas,
    required this.nivelesDemanda,
  });

  factory ContextoCoordinacion.fromJson(Map<String, dynamic> j) => ContextoCoordinacion(
        sedes: [for (final x in _lista(j['sedes'])) Opcion.fromJson(x)],
        areas: [for (final x in _lista(j['areas'])) Opcion.fromJson(x)],
        terapeutas: [for (final x in _lista(j['terapeutas'])) Opcion.fromJson(x)],
        programas: [for (final x in _lista(j['programas'])) Opcion.fromJson(x)],
        nivelesDemanda: [for (final x in _lista(j['niveles_demanda'])) Opcion.fromJson(x)],
      );

  final List<Opcion> sedes, areas, terapeutas, programas, nivelesDemanda;

  List<Opcion> terapeutasDeArea(String? areaId) => areaId == null
      ? terapeutas
      : terapeutas.where((t) => (t.extra['areas'] as List).contains(areaId)).toList();
}

class SesionCoordinacion {
  const SesionCoordinacion({
    required this.id,
    required this.inicio,
    required this.fin,
    required this.tipo,
    required this.estado,
    required this.cupo,
    required this.sede,
    required this.profesionalId,
    required this.terapeuta,
    required this.participantes,
    this.programa,
    this.grupo,
  });

  factory SesionCoordinacion.fromJson(Map<String, dynamic> j) => SesionCoordinacion(
        id: j['id'] as String,
        inicio: j['inicio'] as String,
        fin: j['fin'] as String,
        tipo: j['tipo'] as String,
        estado: j['estado'] as String,
        cupo: j['cupo_maximo'] as int,
        sede: j['sede'] as String,
        profesionalId: j['profesional_id'] as String,
        terapeuta: j['terapeuta'] as String,
        programa: j['programa'] as String?,
        grupo: j['grupo'] as String?,
        participantes: _lista(j['participantes']),
      );

  final String id, inicio, fin, tipo, estado, sede, profesionalId, terapeuta;
  final int cupo;
  final String? programa, grupo;
  final List<Map<String, dynamic>> participantes;
}

/// Una hora del día de un terapeuta: LIBRE, OCUPADO, PAUSA, AUSENCIA o FERIADO.
class HoraDisponible {
  const HoraDisponible({required this.hora, required this.estado, required this.sede, this.programa, this.cupo, this.ocupados});

  factory HoraDisponible.fromJson(Map<String, dynamic> j) => HoraDisponible(
        hora: j['hora'] as String,
        estado: j['estado'] as String,
        sede: j['sede'] as String,
        programa: j['programa'] as String?,
        cupo: j['cupo_maximo'] as int?,
        ocupados: j['ocupados'] as int?,
      );

  final String hora, estado, sede;
  final String? programa;
  final int? cupo, ocupados;

  /// Libre, o grupal con cupo disponible.
  bool get agendable => estado == 'LIBRE' || (estado == 'OCUPADO' && (cupo ?? 1) > (ocupados ?? 0));
}
