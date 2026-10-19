import 'package:centro_psicologia/features/coordinacion/domain/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Semana del lunes 12 al sábado 17 de octubre de 2026 de un profesional
/// de 08:00 a 17:00 con almuerzo de 13:00 a 14:00 los lunes.
SemanaHorario semanaDe({required int minutosTurno, List<Map<String, Object?>> sesiones = const []}) => SemanaHorario.fromJson({
      'desde': '2026-10-12',
      'hasta': '2026-10-17',
      'feriados': [
        {'fecha': '2026-10-16', 'nombre': 'Feriado local', 'sede': 'Tumbaco'},
      ],
      'profesionales': [
        {
          'id': 'p1',
          'nombre': 'Natalia Arias',
          'profesion': 'Terapeuta',
          'color': '#B23A48',
          'minutos_turno': minutosTurno,
          'jornadas': [
            for (final d in [1, 2, 3, 4, 5]) {'dia': d, 'sede': 'Tumbaco', 'inicio': '08:00', 'fin': '17:00'},
          ],
          'pausas': [
            {'dia': 1, 'tipo': 'ALMUERZO', 'inicio': '13:00', 'fin': '14:00'},
          ],
          'ausencias': [
            {'tipo': 'PERMISO', 'desde': '2026-10-14T08:00', 'hasta': '2026-10-14T12:00'},
          ],
          'sesiones': sesiones,
        },
      ],
    });

Map<String, Object?> sesion(String inicio, String fin) => {
      'id': 's$inicio', 'tipo': 'PROGRAMA', 'estado': 'PROGRAMADA', 'fecha': '2026-10-12', 'inicio': inicio, 'fin': fin,
      'sede': 'Tumbaco', 'cupo': 5, 'programa': 'Terapia ocupacional grupal', 'grupo': 'G-12',
      'participantes': [
        {
          'participante_id': 'x1', 'paciente_id': 'a1', 'paciente': 'Mateo Andrade', 'asistencia': 'PENDIENTE',
          'contrato': 'NESC 3101', 'edad_meses': 62, 'fase': 'F2', 'observacion': 'Solo por hoy',
        },
      ],
    };

void main() {
  final lunes = DateTime(2026, 10, 12), miercoles = DateTime(2026, 10, 14), viernes = DateTime(2026, 10, 16);

  test('Neuro: turnos de una hora y la sesión de 45 minutos ocupa su turno', () {
    final semana = semanaDe(minutosTurno: 60, sesiones: [sesion('09:00', '09:45')]);
    final p = semana.profesionales.first;
    final franjas = p.franjasDel(lunes, semana.feriados);
    expect(franjas.map((f) => f.hora).toList(), [
      '08:00–09:00', '09:00–10:00', '10:00–11:00', '11:00–12:00', '12:00–13:00', '13:00–14:00',
      '14:00–15:00', '15:00–16:00', '16:00–17:00',
    ]);
    expect(franjas[0].celda.tipo, TipoCelda.libre);
    expect(franjas[1].celda.tipo, TipoCelda.sesion);
    expect(franjas[1].celda.sesion!.participantes.first.contrato, 'NESC 3101');
    expect(franjas[5].celda.tipo, TipoCelda.pausa);
    expect(p.franjasDel(miercoles, semana.feriados).first.celda.tipo, TipoCelda.ausencia);
    expect(p.franjasDel(viernes, semana.feriados).first.celda.tipo, TipoCelda.feriado);
    expect(p.franjasDel(DateTime(2026, 10, 17), semana.feriados), isEmpty);
  });

  test('Terapia de lenguaje: turnos de 45 minutos seguidos que se reinician después del almuerzo', () {
    final semana = semanaDe(minutosTurno: 45);
    final franjas = semana.profesionales.first.franjasDel(lunes, semana.feriados);
    expect(franjas.map((f) => f.hora).toList(), [
      '08:00–08:45', '08:45–09:30', '09:30–10:15', '10:15–11:00', '11:00–11:45', '11:45–12:30',
      '13:00–14:00', // almuerzo
      '14:00–14:45', '14:45–15:30', '15:30–16:15', '16:15–17:00',
    ]);
  });

  test('las horas de trabajo descuentan las pausas', () {
    final p = semanaDe(minutosTurno: 60).profesionales.first;
    expect(p.horasDel(1), 8);
    expect(p.horasDel(2), 9);
    expect(p.horasDel(6), 0);
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
