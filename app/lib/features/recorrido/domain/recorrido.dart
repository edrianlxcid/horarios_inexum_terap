// Recorrido del paciente: valoración inicial → programa → valoración final.
// Lo comparten coordinación (que lo dirige) y los terapeutas (que lo ven).

/// Etapas en el orden del recorrido, con su nombre para la pantalla.
const nombresEtapas = {
  'POR_VALORAR': 'Por valorar',
  'VALORACION_INICIAL': 'En valoración inicial',
  'POR_INGRESAR': 'Listo para su programa',
  'EN_PROGRAMA': 'En programa',
  'POR_VALORACION_FINAL': 'Toca valoración final',
  'VALORACION_FINAL': 'En valoración final',
  'FINALIZADO': 'Finalizado (alta)',
  'RETIRADO': 'Retirado',
};

/// Etapas que piden una acción de coordinación.
const etapasPendientes = {'POR_VALORAR', 'POR_INGRESAR', 'POR_VALORACION_FINAL'};

const nombresResultados = {
  'INGRESA_A_PROGRAMA': 'Ingresa a un programa',
  'NO_REQUIERE': 'No requiere terapia',
  'ALTA': 'Alta',
  'CONTINUA': 'Continúa con un nuevo programa',
  'DERIVADO': 'Derivado',
};

/// Resultados posibles al cerrar una valoración inicial o final.
const resultadosPorTipo = {
  'INICIAL': ['INGRESA_A_PROGRAMA', 'NO_REQUIERE'],
  'FINAL': ['ALTA', 'CONTINUA', 'DERIVADO'],
};

/// Sesiones previstas, agendadas y realizadas de una especialidad en una valoración.
class EspecialidadPlan {
  const EspecialidadPlan({
    required this.subAreaId,
    required this.especialidad,
    required this.previstas,
    required this.agendadas,
    required this.realizadas,
  });

  factory EspecialidadPlan.fromJson(Map<String, dynamic> j) => EspecialidadPlan(
        subAreaId: j['sub_area_id'] as String,
        especialidad: j['especialidad'] as String,
        previstas: (j['previstas'] as num).toInt(),
        agendadas: (j['agendadas'] as num).toInt(),
        realizadas: (j['realizadas'] as num).toInt(),
      );

  final String subAreaId, especialidad;
  final int previstas, agendadas, realizadas;

  /// Sesiones previstas que todavía no se agendan.
  int get porAgendar => (previstas - agendadas - realizadas).clamp(0, previstas);
}

/// Valoración inicial o final de un paciente.
class ValoracionProceso {
  const ValoracionProceso({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.especialidades,
    this.resultado,
    this.conclusion,
    this.programaRecomendado,
    this.programaCerrado,
    this.abiertoEn,
    this.cerradoEn,
  });

  factory ValoracionProceso.fromJson(Map<String, dynamic> j) => ValoracionProceso(
        id: j['id'] as String,
        tipo: j['tipo'] as String,
        estado: j['estado'] as String,
        resultado: j['resultado'] as String?,
        conclusion: j['conclusion'] as String?,
        programaRecomendado: j['programa_recomendado'] as String?,
        programaCerrado: j['programa_cerrado'] as String?,
        abiertoEn: j['abierto_en'] as String?,
        cerradoEn: j['cerrado_en'] as String?,
        especialidades: [for (final e in (j['especialidades'] as List)) EspecialidadPlan.fromJson(e as Map<String, dynamic>)],
      );

  final String id, tipo, estado;
  final String? resultado, conclusion, programaRecomendado, programaCerrado, abiertoEn, cerradoEn;
  final List<EspecialidadPlan> especialidades;

  bool get enCurso => estado == 'EN_CURSO';
  String get titulo => tipo == 'INICIAL' ? 'Valoración inicial' : 'Valoración final';
  int get previstas => especialidades.fold(0, (s, e) => s + e.previstas);
  int get realizadas => especialidades.fold(0, (s, e) => s + e.realizadas);
  int get agendadas => especialidades.fold(0, (s, e) => s + e.agendadas);
}

/// "falta 1" o "faltan 3".
String faltan(int n) => n == 1 ? 'falta 1' : 'faltan $n';

/// Una sesión en la línea de tiempo del paciente.
class SesionLinea {
  const SesionLinea({
    required this.participanteId,
    required this.profesionalId,
    required this.inicio,
    required this.futura,
    required this.etapa,
    required this.terapeuta,
    required this.asistencia,
    this.programa,
    this.especialidad,
    this.numero,
    this.total,
    this.observacion,
    this.trabajado,
    this.notaFirmada = false,
  });

  factory SesionLinea.fromJson(Map<String, dynamic> j) => SesionLinea(
        participanteId: j['participante_id'] as String,
        profesionalId: j['profesional_id'] as String,
        inicio: j['inicio'] as String,
        futura: j['futura'] == true,
        etapa: j['etapa'] as String,
        terapeuta: j['terapeuta'] as String,
        asistencia: j['asistencia'] as String,
        programa: j['programa'] as String?,
        especialidad: j['especialidad'] as String?,
        numero: j['numero'] as int?,
        total: j['total'] as int?,
        observacion: j['observacion'] as String?,
        trabajado: j['trabajado'] as String?,
        notaFirmada: j['nota_firmada'] == true,
      );

  final String participanteId, profesionalId, inicio, etapa, terapeuta, asistencia;
  final bool futura, notaFirmada;
  final String? programa, especialidad, observacion, trabajado;
  final int? numero, total;

  bool get esValoracion => etapa != 'PROGRAMA';

  /// "Valoración inicial · Psicología infantil" o el nombre del programa.
  String get titulo => esValoracion
      ? '${etapa == 'VALORACION_FINAL' ? 'Valoración final' : 'Valoración inicial'}${especialidad != null ? ' · $especialidad' : ''}'
      : programa ?? 'Sesión';

  /// "sesión 3 de 24".
  String? get numeroTexto => numero == null ? null : 'sesión $numero${total != null ? ' de $total' : ''}';
}
