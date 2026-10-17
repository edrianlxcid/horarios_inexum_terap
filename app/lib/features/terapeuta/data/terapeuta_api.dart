import '../../../core/network/cliente_api.dart';
import '../../../core/util/formatos.dart';
import '../domain/modelos.dart';

/// Llamadas del portal del terapeuta (/api/v1/terapeuta).
class TerapeutaApi {
  TerapeutaApi(this._cliente);

  final ClienteApi _cliente;
  static const _base = '/api/v1/terapeuta';

  Future<AgendaTerapeuta> agenda(DateTime desde, DateTime hasta) async {
    final d = await _cliente.get<Map<String, dynamic>>(
      '$_base/agenda',
      query: {'desde': Formatos.fechaIso(desde), 'hasta': Formatos.fechaIso(hasta)},
    );
    return AgendaTerapeuta.fromJson(d);
  }

  Future<void> marcarAsistencia(String participanteId, String asistencia) =>
      _cliente.put<dynamic>('$_base/participantes/$participanteId/asistencia', {'asistencia': asistencia});

  Future<NotaSesion> nota(String participanteId) async =>
      NotaSesion.fromJson(await _cliente.get<Map<String, dynamic>>('$_base/participantes/$participanteId/nota'));

  Future<void> guardarNota(
    String participanteId, {
    required String contenido,
    String? resumenFamilia,
    required bool firmar,
    Map<String, int> avances = const {},
  }) =>
      _cliente.put<dynamic>('$_base/participantes/$participanteId/nota', {
        'contenido': contenido,
        'resumen_familia': resumenFamilia,
        'firmar': firmar,
        'avances': [for (final e in avances.entries) {'objetivo_id': e.key, 'nivel': e.value}],
      });

  /// Ficha del paciente: datos, representantes, matrículas, objetivos, notas y tareas.
  Future<Map<String, dynamic>> paciente(String pacienteId) =>
      _cliente.get<Map<String, dynamic>>('$_base/pacientes/$pacienteId');

  Future<void> asignarTarea(String pacienteId, {required String titulo, String? descripcion, String? fechaLimite}) =>
      _cliente.post<dynamic>('$_base/pacientes/$pacienteId/tareas', {
        'titulo': titulo,
        'descripcion': descripcion,
        'fecha_limite': fechaLimite,
      });
}
