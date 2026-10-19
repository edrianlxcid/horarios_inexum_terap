import 'contexto.dart';

/// Un estudiante en una cita, con lo que Coordinación anota en sus horarios:
/// contrato, edad, fase y observación.
class ParticipanteCita {
  const ParticipanteCita({
    required this.id,
    required this.pacienteId,
    required this.paciente,
    required this.asistencia,
    this.numeroSesion,
    this.observacion,
    this.edadMeses,
    this.contrato,
    this.fase,
  });

  factory ParticipanteCita.fromJson(Map<String, dynamic> j) => ParticipanteCita(
        id: j['participante_id'] as String,
        pacienteId: j['paciente_id'] as String,
        paciente: j['paciente'] as String,
        asistencia: j['asistencia'] as String,
        numeroSesion: j['numero_sesion'] as int?,
        observacion: j['observacion'] as String?,
        edadMeses: j['edad_meses'] as int?,
        contrato: j['contrato'] as String?,
        fase: j['fase'] as String?,
      );

  final String id, pacienteId, paciente, asistencia;
  final int? numeroSesion, edadMeses;
  final String? observacion, contrato, fase;
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
        participantes: [for (final p in listaJson(j['participantes'])) ParticipanteCita.fromJson(p)],
      );

  final String id, inicio, fin, tipo, estado, sede, profesionalId, terapeuta;
  final int cupo;
  final String? programa, grupo;
  final List<ParticipanteCita> participantes;
}

/// Un turno del día de un terapeuta: LIBRE, OCUPADO, PAUSA, AUSENCIA o FERIADO.
/// Dura lo que marca su especialidad (60 minutos; 45 en Terapia de lenguaje).
class HoraDisponible {
  const HoraDisponible({
    required this.hora,
    required this.fin,
    required this.estado,
    required this.sede,
    this.pausa,
    this.programa,
    this.cupo,
    this.ocupados,
  });

  factory HoraDisponible.fromJson(Map<String, dynamic> j) => HoraDisponible(
        hora: j['hora'] as String,
        fin: j['fin'] as String,
        estado: j['estado'] as String,
        pausa: j['pausa'] as String?,
        sede: j['sede'] as String,
        programa: j['programa'] as String?,
        cupo: j['cupo_maximo'] as int?,
        ocupados: j['ocupados'] as int?,
      );

  final String hora, fin, estado, sede;
  final String? pausa, programa;
  final int? cupo, ocupados;

  /// Libre, o grupal con cupo disponible.
  bool get agendable => estado == 'LIBRE' || (estado == 'OCUPADO' && (cupo ?? 1) > (ocupados ?? 0));
}
