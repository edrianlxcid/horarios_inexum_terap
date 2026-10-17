import '../../../core/network/cliente_api.dart';
import '../domain/modelos.dart';

/// Llamadas del panel de gerencia (/api/v1/gerencia).
class GerenciaApi {
  GerenciaApi(this._cliente);

  final ClienteApi _cliente;
  static const _base = '/api/v1/gerencia';

  Future<PanelGerencia> panel({String? fecha}) async =>
      PanelGerencia.fromJson(await _cliente.get<Map<String, dynamic>>('$_base/panel', query: {'fecha': fecha}));

  Future<Map<String, dynamic>> bonos({String? periodo}) =>
      _cliente.get<Map<String, dynamic>>('$_base/bonos', query: {'periodo': periodo});

  Future<int> recalcular() async => (await _cliente.post<Map<String, dynamic>>('$_base/recalcular', null))['valores'] as int;
}
