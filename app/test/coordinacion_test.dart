import 'package:centro_psicologia/features/coordinacion/domain/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lunes 12 a sábado 17 de octubre de 2026.
  final semana = SemanaHorario.fromJson({
    'desde': '2026-10-12',
    'hasta': '2026-10-17',
    'feriados': [
      {'fecha': '2026-10-16', 'nombre': 'Feriado local', 'sede': 'Tumbaco'},
    ],
    'profesionales': [
      {
        'id': 'p1',
        'nombre': 'Natalia Arias',
        'profesion': 'Terapeuta de lenguaje',
        'color': '#B23A48',
        'jornadas': [
          for (final d in [1, 2, 3, 4, 5]) {'dia': d, 'sede': 'Tumbaco', 'inicio': '08:00', 'fin': '17:00'},
        ],
        'pausas': [
          {'dia': 1, 'tipo': 'ALMUERZO', 'inicio': '13:00', 'fin': '14:00'},
        ],
        'ausencias': [
          {'tipo': 'PERMISO', 'desde': '2026-10-14T08:00', 'hasta': '2026-10-14T12:00'},
        ],
        'sesiones': [
          {
            'id': 's1', 'tipo': 'PROGRAMA', 'estado': 'PROGRAMADA', 'fecha': '2026-10-12', 'inicio': '09:00', 'fin': '10:00',
            'sede': 'Tumbaco', 'cupo': 5, 'programa': 'Terapia ocupacional grupal', 'grupo': 'G-12',
            'participantes': ['Mateo Andrade', 'Emilia Paredes'],
          },
        ],
      },
    ],
  });
  final p = semana.profesionales.first;
  final lunes = DateTime(2026, 10, 12), miercoles = DateTime(2026, 10, 14), viernes = DateTime(2026, 10, 16);

  test('cada hora del horario sabe qué tiene', () {
    expect(p.celda(lunes, 7, semana.feriados).tipo, TipoCelda.fuera);
    expect(p.celda(lunes, 8, semana.feriados).tipo, TipoCelda.libre);
    final sesion = p.celda(lunes, 9, semana.feriados);
    expect(sesion.tipo, TipoCelda.sesion);
    expect(sesion.sesion!.participantes, hasLength(2));
    expect(p.celda(lunes, 13, semana.feriados).tipo, TipoCelda.pausa);
    expect(p.celda(miercoles, 10, semana.feriados).tipo, TipoCelda.ausencia);
    expect(p.celda(miercoles, 12, semana.feriados).tipo, TipoCelda.libre);
    expect(p.celda(viernes, 10, semana.feriados).tipo, TipoCelda.feriado);
    expect(p.celda(DateTime(2026, 10, 17), 10, semana.feriados).tipo, TipoCelda.fuera);
  });

  test('las horas de trabajo descuentan las pausas', () {
    expect(p.horasDel(1), 8);
    expect(p.horasDel(2), 9);
    expect(p.horasDel(6), 0);
    expect(semana.rangoHoras([p]), (8, 17));
    expect(semana.dias, hasLength(6));
  });

  test('cambiar un filtro de estudiantes vuelve a la primera página', () {
    const filtro = FiltroEstudiantes(q: 'andrade', pagina: 3);
    final nuevo = filtro.con(sede: () => 'sede-1');
    expect(nuevo.pagina, 1);
    expect(nuevo.q, 'andrade');
    expect(nuevo.sede, 'sede-1');
    expect(nuevo.con(sede: () => null).sede, isNull);
    expect(filtro.enPagina(2).consulta['pagina'], 2);
  });

  test('el horario de un profesional nuevo se arma por bloques', () {
    final bloque = BloqueHorario(sedeId: 's1', dias: {5, 1, 3}, inicio: '08:00', fin: '13:00');
    expect(bloque.jornadas.map((j) => j['dia']), [1, 3, 5]);
    expect(bloque.jornadas.first, {'dia': 1, 'sede_id': 's1', 'inicio': '08:00', 'fin': '13:00'});
  });
}
