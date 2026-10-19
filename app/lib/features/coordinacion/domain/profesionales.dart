import 'package:flutter/material.dart' show Color;

/// Una fila del listado de profesionales con su carga de la semana actual.
class ProfesionalFila {
  const ProfesionalFila({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.profesion,
    required this.color,
    required this.tieneCuenta,
    required this.especialidades,
    required this.sedes,
    required this.horasSemana,
    required this.sesionesSemana,
    required this.horasOcupadas,
    required this.pacientes,
    this.telefono,
    this.email,
  });

  factory ProfesionalFila.fromJson(Map<String, dynamic> j) => ProfesionalFila(
        id: j['id'] as String,
        nombres: j['nombres'] as String,
        apellidos: j['apellidos'] as String,
        profesion: j['profesion'] as String,
        color: colorDe(j['color'] as String?),
        telefono: j['telefono'] as String?,
        email: j['email'] as String?,
        tieneCuenta: j['tiene_cuenta'] == true,
        especialidades: (j['especialidades'] as List).cast<String>(),
        sedes: (j['sedes'] as List).cast<String>(),
        horasSemana: (j['horas_semana'] as num?)?.toDouble() ?? 0,
        sesionesSemana: (j['sesiones_semana'] as num?)?.toInt() ?? 0,
        horasOcupadas: (j['horas_ocupadas'] as num?)?.toDouble() ?? 0,
        pacientes: (j['pacientes'] as num?)?.toInt() ?? 0,
      );

  final String id, nombres, apellidos, profesion;
  final Color color;
  final String? telefono, email;
  final bool tieneCuenta;
  final List<String> especialidades, sedes;
  final double horasSemana, horasOcupadas;
  final int sesionesSemana, pacientes;

  String get nombre => '$nombres $apellidos';

  /// Parte de las horas de trabajo de esta semana que ya tiene sesiones (0 a 1).
  double get ocupacion => horasSemana <= 0 ? 0 : (horasOcupadas / horasSemana).clamp(0, 1);
}

/// "#1D5F8A" → Color.
Color colorDe(String? hex) {
  final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | (v ?? 0x1D5F8A));
}

/// Un bloque del horario de un profesional nuevo: los mismos días, sede y horas.
/// Un horario partido (mañana en una sede, sábado en otra) son varios bloques.
class BloqueHorario {
  BloqueHorario({this.sedeId, Set<int>? dias, this.inicio = '08:00', this.fin = '17:00'})
      : dias = dias ?? {1, 2, 3, 4, 5};

  String? sedeId;
  final Set<int> dias;
  String inicio;
  String fin;

  List<Map<String, Object?>> get jornadas =>
      [for (final d in dias.toList()..sort()) {'dia': d, 'sede_id': sedeId, 'inicio': inicio, 'fin': fin}];
}

const nombresDias = {1: 'Lunes', 2: 'Martes', 3: 'Miércoles', 4: 'Jueves', 5: 'Viernes', 6: 'Sábado'};
const inicialesDias = {1: 'L', 2: 'M', 3: 'X', 4: 'J', 5: 'V', 6: 'S'};
