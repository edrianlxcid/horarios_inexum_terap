import 'package:dio/dio.dart';

import '../config/entorno.dart';

/// Error de la API con un mensaje listo para mostrar.
class ErrorApi implements Exception {
  ErrorApi(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP compartido por todos los módulos de la app.
class ClienteApi {
  ClienteApi({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? Entorno.apiUrl,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 20),
            contentType: 'application/json',
          ),
        );

  final Dio _dio;

  Future<T> get<T>(String ruta, {Map<String, dynamic>? query}) =>
      _enviar(() => _dio.get<T>(ruta, queryParameters: query));

  Future<T> post<T>(String ruta, Object? datos) => _enviar(() => _dio.post<T>(ruta, data: datos));

  Future<T> put<T>(String ruta, Object? datos) => _enviar(() => _dio.put<T>(ruta, data: datos));

  Future<T> delete<T>(String ruta) => _enviar(() => _dio.delete<T>(ruta));

  Future<T> _enviar<T>(Future<Response<T>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      return respuesta.data as T;
    } on DioException catch (e) {
      final cuerpo = e.response?.data;
      if (cuerpo is Map && cuerpo['error'] is String) {
        throw ErrorApi(cuerpo['error'] as String);
      }
      if (e.response == null) {
        throw ErrorApi('No se pudo conectar con la API en ${_dio.options.baseUrl}. ¿Está encendida?');
      }
      throw ErrorApi('La API respondió con un error (${e.response?.statusCode}).');
    }
  }
}
