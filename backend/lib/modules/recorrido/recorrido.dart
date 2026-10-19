import 'package:backend/core/db/base_datos.dart';
import 'package:postgres/postgres.dart';

/// Recorrido del paciente: valoración inicial → programa → valoración final.
/// Consultas compartidas por coordinación y por los terapeutas.
class Recorrido {
  const Recorrido._();

  /// Etapa actual (ver agenda.etapa_paciente).
  static Future<String> etapa(Session tx, String pacienteId) async =>
      (await fila(tx, 'SELECT agenda.etapa_paciente(CAST(@id:text AS uuid)) AS etapa', {'id': pacienteId}))!['etapa'] as String;

  /// Valoraciones del paciente con sus sesiones previstas, agendadas y
  /// realizadas por especialidad.
  static Future<List<Map<String, dynamic>>> valoraciones(Session tx, String pacienteId) => filas(tx, '''
    SELECT pv.id::text, pv.tipo, pv.estado, pv.resultado, pv.conclusion,
           pv.programa_recomendado_id::text, rec.nombre AS programa_recomendado, mp.nombre AS programa_cerrado,
           to_char(pv.abierto_en AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD') AS abierto_en,
           to_char(pv.cerrado_en AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD') AS cerrado_en,
           coalesce((
             SELECT json_agg(json_build_object(
                      'sub_area_id', pe.sub_area_id, 'especialidad', sa.nombre, 'previstas', pe.sesiones,
                      'realizadas', (SELECT count(*) FROM agenda.participantes x WHERE x.proceso_valoracion_id = pv.id
                                     AND x.valoracion_especialidad_id = pe.sub_area_id AND x.asistencia IN ('ASISTIO', 'FALTA')),
                      'agendadas', (SELECT count(*) FROM agenda.participantes x WHERE x.proceso_valoracion_id = pv.id
                                    AND x.valoracion_especialidad_id = pe.sub_area_id AND x.asistencia = 'PENDIENTE'))
                    ORDER BY sa.nombre)
             FROM agenda.proceso_especialidades pe JOIN catalogo.sub_areas sa ON sa.id = pe.sub_area_id
             WHERE pe.proceso_id = pv.id), '[]'::json) AS especialidades
    FROM agenda.procesos_valoracion pv
    LEFT JOIN catalogo.programas rec ON rec.id = pv.programa_recomendado_id
    LEFT JOIN matriculas.matriculas m ON m.id = pv.matricula_id
    LEFT JOIN catalogo.programas mp ON mp.id = m.programa_id
    WHERE pv.paciente_id = CAST(@id:text AS uuid) AND pv.estado <> 'CANCELADA'
    ORDER BY pv.abierto_en''', {'id': pacienteId});

  /// Sesiones del paciente (más recientes primero): en qué etapa fue, número
  /// de sesión, con quién, si asistió y qué se trabajó.
  static Future<List<Map<String, dynamic>>> lineaDeTiempo(Session tx, String pacienteId, {int limite = 120}) => filas(tx, '''
    SELECT x.id::text AS participante_id, s.id::text AS sesion_id, s.profesional_id::text,
           to_char(s.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS inicio, s.inicio > now() AS futura,
           CASE pv.tipo WHEN 'INICIAL' THEN 'VALORACION_INICIAL' WHEN 'FINAL' THEN 'VALORACION_FINAL'
                ELSE CASE WHEN s.tipo = 'VALORACION' THEN 'VALORACION_INICIAL' ELSE 'PROGRAMA' END END AS etapa,
           pg.nombre AS programa, esp.nombre AS especialidad, x.numero_sesion AS numero,
           coalesce(m.sesiones_contratadas,
                    (SELECT sum(pe.sesiones) FROM agenda.proceso_especialidades pe WHERE pe.proceso_id = pv.id))::int AS total,
           pr.nombres || ' ' || pr.apellidos AS terapeuta, x.asistencia, x.observacion,
           coalesce(n.resumen_familia, v.conclusion) AS trabajado, n.firmada_en IS NOT NULL AS nota_firmada
    FROM agenda.participantes x
    JOIN agenda.sesiones s ON s.id = x.sesion_id
    JOIN personas.profesionales pr ON pr.id = s.profesional_id
    LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
    LEFT JOIN matriculas.matriculas m ON m.id = x.matricula_id
    LEFT JOIN agenda.procesos_valoracion pv ON pv.id = x.proceso_valoracion_id
    LEFT JOIN catalogo.sub_areas esp ON esp.id = x.valoracion_especialidad_id
    LEFT JOIN clinico.notas_sesion n ON n.participante_id = x.id
    LEFT JOIN clinico.valoraciones v ON v.participante_id = x.id
    WHERE x.paciente_id = CAST(@id:text AS uuid) AND s.estado <> 'CANCELADA'
      AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')
    ORDER BY s.inicio DESC
    LIMIT @limite:int4''', {'id': pacienteId, 'limite': limite});
}
