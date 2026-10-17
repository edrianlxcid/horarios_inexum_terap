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

  Future<List<SesionCoordinacion>> agenda(DateTime dia, {String? area, String? profesional}) async {
    final d = await _cliente.get<List<dynamic>>('$_base/agenda', query: {
      'desde': Formatos.fechaIso(dia),
      'hasta': Formatos.fechaIso(dia),
      'area': area,
      'profesional': profesional,
    });
    return [for (final s in d) SesionCoordinacion.fromJson(s as Map<String, dynamic>)];
  }

  Future<List<HoraDisponible>> disponibilidad(String profesionalId, DateTime dia) async {
    final d = await _cliente.get<List<dynamic>>('$_base/disponibilidad',
        query: {'profesional': profesionalId, 'fecha': Formatos.fechaIso(dia)});
    return [for (final h in d) HoraDisponible.fromJson(h as Map<String, dynamic>)];
  }

  /// {total, pagina, tamano, filas}
  Future<Map<String, dynamic>> pacientes({String q = '', String? area, String? estado, int pagina = 1}) =>
      _cliente.get<Map<String, dynamic>>('$_base/pacientes', query: {'q': q, 'area': area, 'estado': estado, 'pagina': pagina});

  Future<Map<String, dynamic>> paciente(String id) => _cliente.get<Map<String, dynamic>>('$_base/pacientes/$id');

  Future<Map<String, dynamic>> crearPaciente(Map<String, dynamic> datos) =>
      _cliente.post<Map<String, dynamic>>('$_base/pacientes', datos);

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

  Future<List<Map<String, dynamic>>> solicitudes({String estado = 'PENDIENTE', String? area}) async {
    final d = await _cliente.get<List<dynamic>>('$_base/solicitudes', query: {'estado': estado, 'area': area});
    return d.cast<Map<String, dynamic>>();
  }

  Future<void> resolverSolicitud(String id, String estado) =>
      _cliente.put<dynamic>('$_base/solicitudes/$id', {'estado': estado});

  Future<void> clasificarDemanda(String pacienteId, String nivelId, String motivo) =>
      _cliente.post<dynamic>('$_base/demanda', {'paciente_id': pacienteId, 'nivel_id': nivelId, 'motivo': motivo});
}
