import '../../../core/network/cliente_api.dart';
import '../domain/modelos.dart';

/// Llamadas a la edición genérica de tablas de la API. Se usa con dos bases:
/// /api/dev/datos (herramienta de desarrollo) y /api/v1/admin/datos (Administración).
class DatosApi {
  // Un parámetro con nombre no puede ser privado, por eso se asigna aparte.
  // ignore: prefer_initializing_formals
  DatosApi(this._cliente, {String base = '/api/dev/datos'}) : _base = base;

  final ClienteApi _cliente;
  final String _base;

  Future<List<Tabla>> tablas() async {
    final datos = await _cliente.get<List<dynamic>>('$_base/tablas');
    return [for (final t in datos) Tabla.fromJson(t as Map<String, dynamic>)];
  }

  Future<PaginaFilas> filas(Tabla tabla, {String busqueda = '', int pagina = 1, int tamano = 25}) async {
    final datos = await _cliente.get<Map<String, dynamic>>(
      '$_base/tablas/${tabla.esquema}/${tabla.tabla}',
      query: {'q': busqueda, 'pagina': pagina, 'tamano': tamano},
    );
    return PaginaFilas.fromJson(datos);
  }

  Future<List<Opcion>> opciones(Referencia ref, String busqueda) async {
    final datos = await _cliente.get<List<dynamic>>(
      '$_base/opciones/${ref.esquema}/${ref.tabla}',
      query: {'q': busqueda},
    );
    return [
      for (final o in datos.cast<Map<String, dynamic>>()) Opcion(o['valor'] as String, (o['etiqueta'] ?? o['valor']) as String),
    ];
  }

  Future<void> crear(Tabla tabla, Map<String, dynamic> valores) =>
      _cliente.post<dynamic>('$_base/tablas/${tabla.esquema}/${tabla.tabla}', valores);

  Future<void> actualizar(Tabla tabla, Map<String, dynamic> fila, Map<String, dynamic> valores) =>
      _cliente.put<dynamic>('$_base/tablas/${tabla.esquema}/${tabla.tabla}/${tabla.claveDe(fila)}', valores);

  /// Devuelve "archivado" o "eliminado".
  Future<String> eliminar(Tabla tabla, Map<String, dynamic> fila) async {
    final r = await _cliente.delete<Map<String, dynamic>>(
      '$_base/tablas/${tabla.esquema}/${tabla.tabla}/${tabla.claveDe(fila)}',
    );
    return r['resultado'] as String;
  }
}
