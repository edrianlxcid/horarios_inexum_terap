import 'dart:convert';

import 'package:centro_psicologia/features/herramienta_datos/domain/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tabla = Tabla.fromJson({
    'esquema': 'personas',
    'tabla': 'paciente_representantes',
    'descripcion': null,
    'soloLectura': false,
    'archivable': false,
    'columnas': [
      {
        'nombre': 'paciente_id', 'tipo': 'referencia', 'tipoSql': 'uuid', 'requerido': true, 'esClave': true,
        'editable': true, 'referencia': {'esquema': 'personas', 'tabla': 'pacientes', 'columna': 'id'},
      },
      {
        'nombre': 'representante_id', 'tipo': 'referencia', 'tipoSql': 'uuid', 'requerido': true, 'esClave': true,
        'editable': true, 'referencia': {'esquema': 'personas', 'tabla': 'representantes', 'columna': 'id'},
      },
      {
        'nombre': 'parentesco', 'tipo': 'opcion', 'tipoSql': 'text', 'requerido': true, 'esClave': false,
        'editable': true, 'opciones': ['MADRE', 'PADRE'],
      },
    ],
  });

  test('la clave compuesta viaja como JSON en base64url', () {
    final clave = tabla.claveDe({'paciente_id': 'a', 'representante_id': 'b', 'parentesco': 'MADRE'});
    final decodificada = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(clave))));
    expect(decodificada, {'paciente_id': 'a', 'representante_id': 'b'});
  });

  test('los títulos se vuelven legibles', () {
    expect(tabla.titulo, 'Paciente representantes');
    expect(tabla.columnas.first.titulo, 'Paciente');
    expect(tabla.modulo, 'Personas');
  });

  test('el título de un registro usa la etiqueta de su relación', () {
    final fila = {'paciente_id': 'x', 'paciente_id__etiqueta': 'Mateo Andrade'};
    expect(tabla.tituloDe(fila), 'Mateo Andrade');
  });
}
