import 'package:dio/dio.dart';

import '../config/entorno.dart';

/// Error de la API con un mensaje listo para mostrar.
class ErrorApi implements Exception {
  ErrorApi(this.mensaje, {this.estado});

  final String mensaje;
  final int? estado;

  @override
  String toString() => mensaje;
}

/// Lo que el cliente necesita saber de la sesión: el token, la empresa
/// activa y cómo renovar el token cuando vence. Lo implementa SesionControlador.
abstract interface class ProveedorSesion {
  String? get tokenAcceso;
  String? get empresaId;
  Future<bool> renovar();
}

/// Cliente HTTP compartido por todos los módulos de la app.
/// - Agrega Authorization y X-Empresa-Id a cada petición.
/// - Si la API responde 401, renueva la sesión una vez y repite la petición.
/// - Convierte los errores en [ErrorApi] con el mensaje en español de la API.
class ClienteApi {
  ClienteApi({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? Entorno.apiUrl,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 25),
            contentType: 'application/json',
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (opciones, siguiente) {
          final s = sesion;
          if (s != null && opciones.extra['publica'] != true) {
            final token = s.tokenAcceso;
            if (token != null) opciones.headers['Authorization'] = 'Bearer $token';
          }
          final empresa = s?.empresaId;
          if (empresa != null) opciones.headers['X-Empresa-Id'] = empresa;
          siguiente.next(opciones);
        },
        onError: (error, siguiente) async {
          final s = sesion;
          final o = error.requestOptions;
          final reintentable = error.response?.statusCode == 401 && o.extra['publica'] != true && o.extra['reintento'] != true;
          if (s != null && reintentable && await s.renovar()) {
            o.extra['reintento'] = true;
            try {
              return siguiente.resolve(await _dio.fetch<dynamic>(o));
            } on DioException catch (e) {
              return siguiente.next(e);
            }
          }
          siguiente.next(error);
        },
      ),
    );
  }

  final Dio _dio;

  /// Se asigna al crear el controlador de sesión.
  ProveedorSesion? sesion;

  String get baseUrl => _dio.options.baseUrl;

  Future<T> get<T>(String ruta, {Map<String, dynamic>? query, bool publica = false}) =>
      _enviar(() => _dio.get<T>(ruta, queryParameters: _sinNulos(query), options: _opciones(publica)));

  Future<T> post<T>(String ruta, Object? datos, {bool publica = false}) =>
      _enviar(() => _dio.post<T>(ruta, data: datos, options: _opciones(publica)));

  Future<T> put<T>(String ruta, Object? datos) => _enviar(() => _dio.put<T>(ruta, data: datos));

  Future<T> delete<T>(String ruta) => _enviar(() => _dio.delete<T>(ruta));

  static Options _opciones(bool publica) => Options(extra: {'publica': publica});

  static Map<String, dynamic>? _sinNulos(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null || v == ''));

  Future<T> _enviar<T>(Future<Response<T>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      return respuesta.data as T;
    } on DioException catch (e) {
      final cuerpo = e.response?.data;
      final estado = e.response?.statusCode;
      if (cuerpo is Map && cuerpo['error'] is String) {
        throw ErrorApi(cuerpo['error'] as String, estado: estado);
      }
      if (e.response == null) {
        throw ErrorApi('No se pudo conectar con la API en ${_dio.options.baseUrl}. ¿Está encendida?');
      }
      throw ErrorApi('La API respondió con un error ($estado).', estado: estado);
    }
  }
}
