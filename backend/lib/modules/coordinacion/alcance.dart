import 'dart:convert';

import 'package:backend/core/auth/sesion.dart';

/// Sedes y áreas que coordina el usuario, opcionalmente reducidas a un área
/// elegida en la pantalla ("cambiar de interfaz"). Toda consulta de
/// coordinación se filtra con este alcance: un coordinador de Neuro no ve
/// lo de Estimulación, y uno de la sede Norte no ve la sede Villaflora.
///
/// Las condiciones SQL usan los parámetros @alcance y @area, que vienen en
/// [parametros].
class Alcance {
  Alcance._(this.pares, this.parametros);

  factory Alcance.de(Sesion s, {String? area}) {
    final pares = s.alcance('COORDINADOR');
    if (pares.isEmpty) throw ErrorAcceso(403, 'Necesitas el rol de coordinación.');
    if (area != null && area.isNotEmpty && !pares.any((p) => p['area'] == null || p['area'] == area)) {
      throw ErrorAcceso(403, 'No coordinas esa área.');
    }
    return Alcance._(pares, {'alcance': jsonEncode(pares), 'area': area ?? ''});
  }

  /// Pares (sede, área); un valor nulo significa "todas".
  final List<Map<String, String?>> pares;

  /// Parámetros @alcance y @area para las consultas.
  final Map<String, Object?> parametros;

  static const _pares = 'jsonb_to_recordset(CAST(@alcance:text AS jsonb)) a(sede uuid, area uuid)';
  static const _areaElegida = "CAST(nullif(@area:text, '') AS uuid)";

  /// La sede y el área caen dentro del alcance y en el área elegida.
  static String sedeYArea(String sede, String area) => '''
    EXISTS (SELECT 1 FROM $_pares WHERE (a.sede IS NULL OR a.sede = $sede) AND (a.area IS NULL OR a.area = $area))
    AND (@area:text = '' OR $area = $_areaElegida)''';

  /// La sede está dentro del alcance.
  static String sede(String sede) => 'EXISTS (SELECT 1 FROM $_pares WHERE a.sede IS NULL OR a.sede = $sede)';

  /// El área está dentro del alcance y en el área elegida.
  static String area(String area) => '''
    EXISTS (SELECT 1 FROM $_pares WHERE a.area IS NULL OR a.area = $area)
    AND (@area:text = '' OR $area = $_areaElegida)''';

  /// Jornada vigente hoy o que empieza más adelante.
  static String jornadaVigente(String j) => "coalesce($j.vigente_hasta, 'infinity') >= current_date";

  /// El profesional trabaja (jornada vigente) en una sede del alcance con una
  /// especialidad de un área del alcance.
  static String profesional(String id) => '''
    EXISTS (SELECT 1 FROM agenda.jornadas j
            JOIN personas.profesional_sub_areas psa ON psa.profesional_id = j.profesional_id
            JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id
            WHERE j.profesional_id = $id AND ${jornadaVigente('j')} AND ${sedeYArea('j.sede_id', 'sa.area_id')})''';

  /// El paciente es de una sede del alcance y, si el coordinador es de un
  /// área, tiene una matrícula de esa área o todavía no tiene ninguna
  /// (prospecto: cualquier coordinador de la sede puede valorarlo).
  static String paciente(String p) => '''
    EXISTS (SELECT 1 FROM $_pares
            WHERE (a.sede IS NULL OR a.sede = $p.sede_principal_id)
              AND (a.area IS NULL
                   OR NOT EXISTS (SELECT 1 FROM matriculas.matriculas m WHERE m.paciente_id = $p.id)
                   OR EXISTS (SELECT 1 FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
                              WHERE m.paciente_id = $p.id AND pg.area_id = a.area)))
    AND (@area:text = ''
         OR NOT EXISTS (SELECT 1 FROM matriculas.matriculas m WHERE m.paciente_id = $p.id)
         OR EXISTS (SELECT 1 FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
                    WHERE m.paciente_id = $p.id AND pg.area_id = $_areaElegida))''';
}
