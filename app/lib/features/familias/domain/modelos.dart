List<Map<String, dynamic>> _lista(Object? v) => (v as List).cast<Map<String, dynamic>>();

class Hijo {
  const Hijo({required this.id, required this.nombres, required this.apellidos, required this.sede, this.edadMeses});

  factory Hijo.fromJson(Map<String, dynamic> j) => Hijo(
        id: j['id'] as String,
        nombres: j['nombres'] as String,
        apellidos: j['apellidos'] as String,
        sede: j['sede'] as String,
        edadMeses: j['edad_meses'] as int?,
      );

  final String id, nombres, apellidos, sede;
  final int? edadMeses;
}

class ProximaSesion {
  const ProximaSesion({
    required this.participanteId,
    required this.inicio,
    required this.tipo,
    required this.terapeuta,
    required this.sede,
    required this.solicitudPendiente,
    this.programa,
    this.numeroSesion,
  });

  factory ProximaSesion.fromJson(Map<String, dynamic> j) => ProximaSesion(
        participanteId: j['participante_id'] as String,
        inicio: j['inicio'] as String,
        tipo: j['tipo'] as String,
        terapeuta: j['terapeuta'] as String,
        sede: j['sede'] as String,
        solicitudPendiente: j['solicitud_pendiente'] as bool,
        programa: j['programa'] as String?,
        numeroSesion: j['numero_sesion'] as int?,
      );

  final String participanteId, inicio, tipo, terapeuta, sede;
  final bool solicitudPendiente;
  final String? programa;
  final int? numeroSesion;
}

class ProgramaHijo {
  const ProgramaHijo({required this.programa, required this.estado, required this.contratadas, required this.realizadas, this.fase, this.finEstimado});

  factory ProgramaHijo.fromJson(Map<String, dynamic> j) => ProgramaHijo(
        programa: j['programa'] as String,
        estado: j['estado'] as String,
        contratadas: j['contratadas'] as int,
        realizadas: j['realizadas'] as int,
        fase: j['fase'] as String?,
        finEstimado: j['fin_estimado'] as String?,
      );

  final String programa, estado;
  final int contratadas, realizadas;
  final String? fase, finEstimado;
}

class TareaCasa {
  const TareaCasa({required this.id, required this.titulo, required this.completada, required this.terapeuta, this.descripcion, this.fechaLimite});

  factory TareaCasa.fromJson(Map<String, dynamic> j) => TareaCasa(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        completada: j['completada'] as bool,
        terapeuta: j['terapeuta'] as String,
        descripcion: j['descripcion'] as String?,
        fechaLimite: j['fecha_limite'] as String?,
      );

  final String id, titulo, terapeuta;
  final bool completada;
  final String? descripcion, fechaLimite;
}

class EvaluacionPendiente {
  const EvaluacionPendiente({required this.matriculaId, required this.profesionalId, required this.terapeuta, required this.programa});

  factory EvaluacionPendiente.fromJson(Map<String, dynamic> j) => EvaluacionPendiente(
        matriculaId: j['matricula_id'] as String,
        profesionalId: j['profesional_id'] as String,
        terapeuta: j['terapeuta'] as String,
        programa: j['programa'] as String,
      );

  final String matriculaId, profesionalId, terapeuta, programa;
}

/// Todo lo que la familia ve de un hijo. Sin pagos: solo el contrato vigente.
class ResumenHijo {
  const ResumenHijo({
    required this.proximas,
    required this.programas,
    required this.objetivos,
    required this.tareas,
    required this.historial,
    required this.contratos,
    required this.evaluacionesPendientes,
  });

  factory ResumenHijo.fromJson(Map<String, dynamic> j) => ResumenHijo(
        proximas: [for (final x in _lista(j['proximas_sesiones'])) ProximaSesion.fromJson(x)],
        programas: [for (final x in _lista(j['programas'])) ProgramaHijo.fromJson(x)],
        objetivos: _lista(j['objetivos']),
        tareas: [for (final x in _lista(j['tareas'])) TareaCasa.fromJson(x)],
        historial: _lista(j['historial']),
        contratos: _lista(j['contratos_vigentes']),
        evaluacionesPendientes: [for (final x in _lista(j['evaluaciones_pendientes'])) EvaluacionPendiente.fromJson(x)],
      );

  final List<ProximaSesion> proximas;
  final List<ProgramaHijo> programas;
  final List<Map<String, dynamic>> objetivos;
  final List<TareaCasa> tareas;
  final List<Map<String, dynamic>> historial;
  final List<Map<String, dynamic>> contratos;
  final List<EvaluacionPendiente> evaluacionesPendientes;
}
