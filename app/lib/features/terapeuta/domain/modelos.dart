/// Sesión de la agenda del terapeuta con sus participantes.
class SesionTerapeuta {
  const SesionTerapeuta({
    required this.id,
    required this.inicio,
    required this.fin,
    required this.tipo,
    required this.estado,
    required this.cupo,
    required this.sede,
    required this.participantes,
    this.sala,
    this.programa,
    this.grupo,
  });

  factory SesionTerapeuta.fromJson(Map<String, dynamic> j) => SesionTerapeuta(
        id: j['id'] as String,
        inicio: j['inicio'] as String,
        fin: j['fin'] as String,
        tipo: j['tipo'] as String,
        estado: j['estado'] as String,
        cupo: j['cupo_maximo'] as int,
        sede: j['sede'] as String,
        sala: j['sala'] as String?,
        programa: j['programa'] as String?,
        grupo: j['grupo'] as String?,
        participantes: [
          for (final p in j['participantes'] as List) ParticipanteSesion.fromJson(p as Map<String, dynamic>),
        ],
      );

  final String id, inicio, fin, tipo, estado, sede;
  final int cupo;
  final String? sala, programa, grupo;
  final List<ParticipanteSesion> participantes;
}

class ParticipanteSesion {
  const ParticipanteSesion({
    required this.participanteId,
    required this.pacienteId,
    required this.paciente,
    required this.asistencia,
    required this.nota,
    this.edadMeses,
    this.numeroSesion,
    this.totalSesiones,
    this.fase,
    this.demanda,
    this.valoracion,
    this.especialidad,
    this.trabajado,
  });

  factory ParticipanteSesion.fromJson(Map<String, dynamic> j) => ParticipanteSesion(
        participanteId: j['participante_id'] as String,
        pacienteId: j['paciente_id'] as String,
        paciente: j['paciente'] as String,
        asistencia: j['asistencia'] as String,
        nota: j['nota'] as String,
        edadMeses: j['edad_meses'] as int?,
        numeroSesion: j['numero_sesion'] as int?,
        totalSesiones: j['total_sesiones'] as int?,
        fase: j['fase'] as String?,
        demanda: j['demanda'] as String?,
        valoracion: j['valoracion'] as String?,
        especialidad: j['especialidad'] as String?,
        trabajado: j['trabajado'] as String?,
      );

  final String participanteId, pacienteId, paciente, asistencia;

  /// SIN_NOTA, BORRADOR o FIRMADA.
  final String nota;
  final int? edadMeses, numeroSesion, totalSesiones;
  final String? fase, demanda;

  /// Sesión de valoración: INICIAL o FINAL, y la especialidad que valora.
  final String? valoracion, especialidad;

  /// Lo que se trabajó (resumen de la nota).
  final String? trabajado;
}

class AgendaTerapeuta {
  const AgendaTerapeuta({required this.terapeuta, required this.profesion, required this.sesiones});

  factory AgendaTerapeuta.fromJson(Map<String, dynamic> j) {
    final t = j['terapeuta'] as Map<String, dynamic>;
    return AgendaTerapeuta(
      terapeuta: t['nombre'] as String,
      profesion: t['profesion'] as String,
      sesiones: [for (final s in j['sesiones'] as List) SesionTerapeuta.fromJson(s as Map<String, dynamic>)],
    );
  }

  final String terapeuta, profesion;
  final List<SesionTerapeuta> sesiones;
}

/// Nota de una sesión y los objetivos que se pueden marcar como avanzados.
class NotaSesion {
  const NotaSesion({
    required this.participanteId,
    required this.paciente,
    required this.inicio,
    required this.objetivos,
    this.programa,
    this.numeroSesion,
    this.contenido,
    this.resumenFamilia,
    this.firmadaEn,
  });

  factory NotaSesion.fromJson(Map<String, dynamic> j) => NotaSesion(
        participanteId: j['participante_id'] as String,
        paciente: j['paciente'] as String,
        inicio: j['inicio'] as String,
        programa: j['programa'] as String?,
        numeroSesion: j['numero_sesion'] as int?,
        contenido: j['contenido'] as String?,
        resumenFamilia: j['resumen_familia'] as String?,
        firmadaEn: j['firmada_en'] as String?,
        objetivos: [for (final o in j['objetivos'] as List) ObjetivoNota.fromJson(o as Map<String, dynamic>)],
      );

  final String participanteId, paciente, inicio;
  final String? programa, contenido, resumenFamilia, firmadaEn;
  final int? numeroSesion;
  final List<ObjetivoNota> objetivos;

  bool get firmada => firmadaEn != null;
}

class ObjetivoNota {
  const ObjetivoNota({required this.id, required this.descripcion, required this.estado, this.ultimoNivel});

  factory ObjetivoNota.fromJson(Map<String, dynamic> j) => ObjetivoNota(
        id: j['id'] as String,
        descripcion: j['descripcion'] as String,
        estado: j['estado'] as String,
        ultimoNivel: j['ultimo_nivel'] as int?,
      );

  final String id, descripcion, estado;
  final int? ultimoNivel;
}
