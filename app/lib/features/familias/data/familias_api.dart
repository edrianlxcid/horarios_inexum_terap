import '../../../core/network/cliente_api.dart';
import '../domain/modelos.dart';

/// Llamadas del portal de familias (/api/v1/familia).
class FamiliasApi {
  FamiliasApi(this._cliente);

  final ClienteApi _cliente;
  static const _base = '/api/v1/familia';

  Future<List<Hijo>> hijos() async {
    final d = await _cliente.get<List<dynamic>>('$_base/hijos');
    return [for (final h in d) Hijo.fromJson(h as Map<String, dynamic>)];
  }

  Future<ResumenHijo> resumen(String pacienteId) async =>
      ResumenHijo.fromJson(await _cliente.get<Map<String, dynamic>>('$_base/hijos/$pacienteId'));

  Future<List<(int, String)>> escala() async {
    final d = await _cliente.get<List<dynamic>>('$_base/escala');
    return [for (final e in d.cast<Map<String, dynamic>>()) (e['valor'] as int, e['etiqueta'] as String)];
  }

  Future<void> completarTarea(String tareaId, {String? comentario}) =>
      _cliente.post<dynamic>('$_base/tareas/$tareaId/completar', {'comentario': comentario});

  Future<void> evaluar(EvaluacionPendiente e, {required int puntaje, String? comentario}) =>
      _cliente.post<dynamic>('$_base/evaluaciones', {
        'matricula_id': e.matriculaId,
        'profesional_id': e.profesionalId,
        'puntaje': puntaje,
        'comentario': comentario,
      });

  Future<void> solicitarCambio(String participanteId, {required String tipo, required String motivo, String? propuesta}) =>
      _cliente.post<dynamic>('$_base/solicitudes', {
        'participante_id': participanteId,
        'tipo': tipo,
        'motivo': motivo,
        'propuesta_inicio': propuesta,
      });
}
