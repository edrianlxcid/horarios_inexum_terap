import 'dart:io';

import 'package:backend/core/auth/sesion.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// Respuesta de error con un mensaje claro para el usuario.
Response respuestaError(int estado, String mensaje) =>
    Response.json(statusCode: estado, body: {'error': mensaje});

/// Ejecuta un handler y traduce los errores a respuestas con mensajes en español.
Future<Response> conErrores(Future<Response> Function() accion) async {
  try {
    return await accion();
  } on ErrorAcceso catch (e) {
    return respuestaError(e.estado, e.mensaje);
  } on ErrorDatos catch (e) {
    return respuestaError(e.estado, e.mensaje);
  } on ServerException catch (e) {
    return respuestaError(HttpStatus.unprocessableEntity, traducirError(e));
  } on FormatException catch (e) {
    return respuestaError(HttpStatus.badRequest, 'Datos con formato no válido: ${e.message}');
  }
}

/// Cuerpo JSON de la petición como mapa (error 400 si no lo es).
Future<Map<String, dynamic>> cuerpoJson(RequestContext context) async {
  final datos = await context.request.json();
  if (datos is! Map) throw ErrorDatos(HttpStatus.badRequest, 'Se esperaba un objeto JSON.');
  return datos.cast<String, dynamic>();
}

/// Valor obligatorio del cuerpo.
T requerido<T>(Map<String, dynamic> datos, String campo) {
  final v = datos[campo];
  if (v == null || (v is String && v.trim().isEmpty)) {
    throw ErrorDatos(HttpStatus.unprocessableEntity, 'Falta completar "$campo".');
  }
  if (v is! T) throw ErrorDatos(HttpStatus.unprocessableEntity, 'El campo "$campo" no tiene el formato correcto.');
  return v;
}

Response metodoNoPermitido() => Response(statusCode: HttpStatus.methodNotAllowed);

String traducirError(ServerException e) {
  final columna = e.columnName == null ? '' : ' "${e.columnName}"';
  return switch (e.code) {
    // Reglas propias (disparadores): el mensaje ya está en español.
    '23514' when !(e.message.contains('viola la restricción') || e.message.contains('violates check')) => e.message,
    '23514' => 'El valor no cumple una regla de la tabla (${e.constraintName}).',
    '23P01' => e.constraintName == 'sesiones_sin_choque'
        ? 'Choque de horario: el terapeuta ya tiene otra sesión en ese horario.'
        : 'El registro se superpone con otro existente (${e.constraintName}).',
    '23505' => 'Ya existe un registro con ese valor. ${e.detail ?? ''}'.trim(),
    '23503' => e.message.contains('update or delete') || e.message.contains('actualizar o eliminar')
        ? 'No se puede quitar: otros registros dependen de este.'
        : 'El registro relacionado$columna no existe.',
    '23502' => 'Falta completar$columna.',
    '42501' => e.message.contains('row-level security') || e.message.contains('seguridad de filas')
        ? 'No puedes modificar datos de otra empresa.'
        : 'Esta acción no está permitida (permisos de la base de datos).',
    '22P02' || '22007' || '22008' || '22003' => 'Formato no válido$columna: ${e.message}',
    _ => e.message,
  };
}
