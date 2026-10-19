import '../../../core/network/cliente_api.dart';
import '../../../core/util/formatos.dart';
import '../domain/modelos.dart';

/// Llamadas de coordinación (/api/v1/coordinacion). El área elegida en la
/// pantalla se envía como filtro; la API valida que esté en el alcance.
class CoordinacionApi {
  CoordinacionApi(this._cliente);

  final ClienteApi _cliente;
  static const _base = '/api/v1/coordinacion';

  Future<ContextoCoordinacion> contexto() async =>
      ContextoCoordinacion.fromJson(await _cliente.get<Map<String, dynamic>>('$_base/contexto'));

  // ---------------------------------------------------------------------------
  // Agenda y horarios
  // ---------------------------------------------------------------------------
  Future<List<SesionCoordinacion>> agenda(DateTime dia, {String? area, String? profesional}) async {
    final d = await _cliente.get<List<dynamic>>('$_base/agenda', query: {
      'desde': Formatos.fechaIso(dia),
      'hasta': Formatos.fechaIso(dia),
      'area': area,
      'profesional': profesional,
    });
    return [for (final s in d) SesionCoordinacion.fromJson(s as Map<String, dynamic>)];
  }

  /// Horario de lunes a sábado de la semana que contiene [dia].
  Future<SemanaHorario> horarios(DateTime dia, {String? area, String? sede, String? profesional}) async =>
      SemanaHorario.fromJson(await _cliente.get<Map<String, dynamic>>('$_base/horarios', query: {
        'semana': Formatos.fechaIso(dia),
        'area': area,
        'sede': sede,
        'profesional': profesional,
      }));

  Future<List<HoraDisponible>> disponibilidad(String profesionalId, DateTime dia) async {
    final d = await _cliente.get<List<dynamic>>('$_base/disponibilidad',
        query: {'profesional': profesionalId, 'fecha': Formatos.fechaIso(dia)});
    return [for (final h in d) HoraDisponible.fromJson(h as Map<String, dynamic>)];
  }

  Future<Map<String, dynamic>> agendar({
    required String pacienteId,
    required String profesionalId,
    required String inicio,
    required String tipo,
    String? matriculaId,
  }) =>
      _cliente.post<Map<String, dynamic>>('$_base/sesiones', {
        'paciente_id': pacienteId,
        'profesional_id': profesionalId,
        'inicio': inicio,
        'tipo': tipo,
        'matricula_id': matriculaId,
      });

  Future<void> cancelarSesion(String sesionId, String motivo) =>
      _cliente.post<dynamic>('$_base/sesiones/$sesionId/cancelar', {'motivo': motivo});

  // ---------------------------------------------------------------------------
  // Estudiantes (pacientes)
  // ---------------------------------------------------------------------------
  Future<PaginaEstudiantes> estudiantes(FiltroEstudiantes filtro, {String? area}) async => PaginaEstudiantes.fromJson(
      await _cliente.get<Map<String, dynamic>>('$_base/pacientes', query: {...filtro.consulta, 'area': area}));

  /// Ficha completa: datos, representantes, contratos, matrículas, asistencia y sesiones.
  Future<Map<String, dynamic>> estudiante(String id) => _cliente.get<Map<String, dynamic>>('$_base/pacientes/$id');

  /// Devuelve {id, codigo_historia} del estudiante creado.
  Future<Map<String, dynamic>> crearEstudiante(Map<String, dynamic> datos) =>
      _cliente.post<Map<String, dynamic>>('$_base/pacientes', datos);

  Future<void> clasificarDemanda(String pacienteId, String nivelId, String motivo) =>
      _cliente.post<dynamic>('$_base/demanda', {'paciente_id': pacienteId, 'nivel_id': nivelId, 'motivo': motivo});

  // ---------------------------------------------------------------------------
  // Profesionales
  // ---------------------------------------------------------------------------
  Future<List<ProfesionalFila>> profesionales({String q = '', String? area, String? sede}) async {
    final d = await _cliente.get<List<dynamic>>('$_base/profesionales', query: {'q': q, 'area': area, 'sede': sede});
    return [for (final p in d) ProfesionalFila.fromJson(p as Map<String, dynamic>)];
  }

  /// Ficha: datos, especialidades, jornadas, pausas, ausencias y pacientes.
  Future<Map<String, dynamic>> profesional(String id) => _cliente.get<Map<String, dynamic>>('$_base/profesionales/$id');

  /// Devuelve el id del profesional creado.
  Future<String> crearProfesional(Map<String, dynamic> datos) async =>
      (await _cliente.post<Map<String, dynamic>>('$_base/profesionales', datos))['id'] as String;

  // ---------------------------------------------------------------------------
  // Solicitudes de cambio
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> solicitudes({String estado = 'PENDIENTE', String? area}) async {
    final d = await _cliente.get<List<dynamic>>('$_base/solicitudes', query: {'estado': estado, 'area': area});
    return d.cast<Map<String, dynamic>>();
  }

  Future<void> resolverSolicitud(String id, String estado) =>
      _cliente.put<dynamic>('$_base/solicitudes/$id', {'estado': estado});
}
