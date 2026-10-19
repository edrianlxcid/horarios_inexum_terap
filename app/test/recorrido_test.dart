import 'package:centro_psicologia/features/recorrido/domain/recorrido.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una valoración suma lo previsto, lo hecho y lo que falta agendar por especialidad', () {
    final v = ValoracionProceso.fromJson({
      'id': 'v1',
      'tipo': 'INICIAL',
      'estado': 'EN_CURSO',
      'especialidades': [
        {'sub_area_id': 'psico', 'especialidad': 'Psicología infantil', 'previstas': 3, 'agendadas': 1, 'realizadas': 1},
        {'sub_area_id': 'to', 'especialidad': 'Terapia ocupacional', 'previstas': 2, 'agendadas': 0, 'realizadas': 2},
      ],
    });
    expect(v.enCurso, isTrue);
    expect(v.titulo, 'Valoración inicial');
    expect(v.previstas, 5);
    expect(v.realizadas, 3);
    expect(v.especialidades.first.porAgendar, 1);
    expect(v.especialidades.last.porAgendar, 0);
  });

  test('cada sesión de la línea de tiempo dice en qué etapa fue', () {
    SesionLinea sesion(Map<String, Object?> extra) => SesionLinea.fromJson({
          'participante_id': 'x', 'profesional_id': 'p', 'inicio': '2026-10-12T09:00', 'futura': false,
          'terapeuta': 'Ana Prueba', 'asistencia': 'ASISTIO', ...extra,
        });
    final valoracion = sesion({'etapa': 'VALORACION_INICIAL', 'especialidad': 'Psicología infantil', 'numero': 2, 'total': 3});
    expect(valoracion.esValoracion, isTrue);
    expect(valoracion.titulo, 'Valoración inicial · Psicología infantil');
    expect(valoracion.numeroTexto, 'sesión 2 de 3');
    final programa = sesion({'etapa': 'PROGRAMA', 'programa': 'Terapia de lenguaje', 'numero': 14, 'total': 24});
    expect(programa.esValoracion, isFalse);
    expect(programa.titulo, 'Terapia de lenguaje');
    expect(sesion({'etapa': 'VALORACION_FINAL'}).titulo, 'Valoración final');
  });

  test('los resultados dependen del tipo de valoración', () {
    expect(resultadosPorTipo['INICIAL'], contains('INGRESA_A_PROGRAMA'));
    expect(resultadosPorTipo['FINAL'], containsAll(['ALTA', 'CONTINUA']));
    expect(nombresEtapas.keys.first, 'POR_VALORAR');
  });
}
