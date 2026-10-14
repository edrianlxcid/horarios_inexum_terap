-- =============================================================================
-- 100 · Indicadores de Gerencia y Coordinación
-- Cada indicador tiene su fórmula escrita para poder verificarlo. Cada noche se
-- guarda el valor del día: el panel carga rápido y se ve la evolución.
-- Este módulo NO lee datos clínicos.
-- =============================================================================

CREATE SCHEMA reportes;
COMMENT ON SCHEMA reportes IS 'Catálogo de indicadores, metas y valores diarios. Sin acceso a datos clínicos.';

CREATE TABLE reportes.indicadores (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo         text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z0-9_]+$'),
  nombre         text NOT NULL,
  descripcion    text NOT NULL,
  formula        text NOT NULL,
  unidad         text NOT NULL CHECK (unidad IN ('PORCENTAJE', 'NUMERO', 'HORAS', 'PUNTAJE', 'DOLARES')),
  dimension      text NOT NULL CHECK (dimension IN ('SEDE', 'SEDE_AREA', 'PROFESIONAL', 'PROGRAMA', 'SUB_AREA')),
  roles_visibles text[] NOT NULL,
  activo         boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE reportes.indicadores IS 'Qué se mide, cómo se calcula y quién lo ve.';

CREATE TABLE reportes.metas (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  indicador_id uuid NOT NULL REFERENCES reportes.indicadores,
  sede_id      uuid REFERENCES organizacion.sedes,
  area_id      uuid REFERENCES catalogo.areas,
  periodo      date NOT NULL,
  valor_meta   numeric(12,2) NOT NULL,
  UNIQUE NULLS NOT DISTINCT (indicador_id, sede_id, area_id, periodo)
);
COMMENT ON TABLE reportes.metas IS 'Metas por indicador, sede, área y mes.';

CREATE TABLE reportes.valores_indicador (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  indicador_id uuid NOT NULL REFERENCES reportes.indicadores,
  fecha        date NOT NULL,
  sede_id      uuid REFERENCES organizacion.sedes,
  area_id      uuid REFERENCES catalogo.areas,
  dimension_id uuid,
  valor        numeric(12,2) NOT NULL,
  calculado_en timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (indicador_id, fecha, sede_id, area_id, dimension_id)
);
COMMENT ON TABLE reportes.valores_indicador IS 'Valor de cada indicador por día. dimension_id es el terapeuta, programa o especialidad según el indicador.';
CREATE INDEX valores_indicador_fecha ON reportes.valores_indicador (indicador_id, fecha);

INSERT INTO reportes.indicadores (codigo, nombre, descripcion, formula, unidad, dimension, roles_visibles) VALUES
  ('SATURACION_SEDE', 'Saturación por sede', 'Qué parte de las horas de trabajo de la semana está ocupada con sesiones.',
   'Horas de sesiones no canceladas de la semana ÷ (horas de jornada − pausas − feriados) × 100', 'PORCENTAJE', 'SEDE', '{GERENCIA}'),
  ('SATURACION_TERAPEUTA', 'Saturación por terapeuta', 'Ocupación semanal de cada terapeuta.',
   'Horas de sesiones del terapeuta en la semana ÷ sus horas disponibles × 100', 'PORCENTAJE', 'PROFESIONAL', '{GERENCIA,COORDINADOR}'),
  ('SESIONES_SEMANA', 'Sesiones de la semana', 'Sesiones no canceladas en la semana.',
   'Conteo de sesiones con estado distinto de CANCELADA entre lunes y sábado', 'NUMERO', 'SEDE', '{COORDINADOR}'),
  ('PACIENTES_ACTIVOS', 'Pacientes activos', 'Pacientes con al menos una matrícula en curso.',
   'Pacientes distintos con matrícula EN_CURSO, por sede del contrato y área del programa', 'NUMERO', 'SEDE_AREA', '{GERENCIA,COORDINADOR}'),
  ('ASISTENCIA_30D', 'Asistencia (30 días)', 'Porcentaje de asistencia a sesiones realizadas.',
   'ASISTIO ÷ (ASISTIO + FALTA + FALTA_JUSTIFICADA) de los últimos 30 días × 100', 'PORCENTAJE', 'SEDE_AREA', '{COORDINADOR}'),
  ('CANCELACIONES_30D', 'Cancelaciones y reprogramaciones (30 días)', 'Cambios de agenda que afectan a pacientes.',
   'Participaciones CANCELADA o REPROGRAMADA de los últimos 30 días', 'NUMERO', 'SEDE', '{COORDINADOR}'),
  ('OCUPACION_GRUPOS', 'Ocupación de grupos', 'Qué tan llenos están los grupos activos.',
   'Promedio de (miembros vigentes ÷ cupo) de los grupos activos × 100', 'PORCENTAJE', 'SEDE_AREA', '{COORDINADOR}'),
  ('CONTRATOS_POR_VENCER', 'Contratos por vencer', 'Contratos vigentes que vencen en los próximos 30 días.',
   'Contratos VIGENTE con vigente_hasta entre hoy y hoy + 30 días', 'NUMERO', 'SEDE', '{GERENCIA,COORDINADOR}'),
  ('MATRICULAS_NUEVAS_MES', 'Matrículas nuevas del mes', 'Programas vendidos en el mes.',
   'Matrículas con fecha_inicio dentro del mes', 'NUMERO', 'SEDE_AREA', '{GERENCIA}'),
  ('CONVERSION_VALORACION_90D', 'Conversión de valoraciones (90 días)', 'Pacientes valorados que luego se matricularon.',
   'Pacientes con valoración asistida en 90 días que tienen matrícula ÷ pacientes valorados × 100', 'PORCENTAJE', 'SEDE', '{GERENCIA}'),
  ('EVALUACION_TERAPEUTA_90D', 'Evaluación del terapeuta (90 días)', 'Promedio de la evaluación que dan las familias.',
   'Promedio de puntaje de evaluaciones_terapeuta de los últimos 90 días', 'PUNTAJE', 'PROFESIONAL', '{GERENCIA,COORDINADOR}'),
  ('SOLICITUDES_PENDIENTES', 'Solicitudes de cambio pendientes', 'Pedidos de reprogramación o cancelación sin resolver.',
   'Solicitudes con estado PENDIENTE', 'NUMERO', 'SEDE', '{COORDINADOR}'),
  ('PACIENTES_DEMANDA_ALTA', 'Pacientes con demanda alta', 'Pacientes activos clasificados con demanda alta o muy alta.',
   'Pacientes ACTIVO con clasificación vigente de peso ≥ 3', 'NUMERO', 'SEDE', '{GERENCIA,COORDINADOR}'),
  ('CARGA_PROGRAMA_30D', 'Carga por programa (30 días)', 'Sesiones realizadas por programa.',
   'Sesiones REALIZADA de los últimos 30 días agrupadas por programa', 'NUMERO', 'PROGRAMA', '{GERENCIA}'),
  ('ESPECIALIDAD_SOLICITADA_30D', 'Especialidad más solicitada (30 días)', 'Sesiones realizadas por especialidad.',
   'Sesiones REALIZADA de los últimos 30 días agrupadas por la especialidad que exige el programa', 'NUMERO', 'SUB_AREA', '{GERENCIA}'),
  ('RANKING_TERAPEUTAS_30D', 'Pacientes atendidos por terapeuta (30 días)', 'Pacientes distintos atendidos por cada terapeuta.',
   'Pacientes distintos con asistencia ASISTIO en sesiones del terapeuta en 30 días', 'NUMERO', 'PROFESIONAL', '{GERENCIA}'),
  ('RIESGO_NO_COMPLETAR', 'Matrículas en riesgo de no completarse', 'Matrículas a las que no les alcanza el tiempo para usar sus sesiones.',
   'Matrículas EN_CURSO con sesiones pendientes > semanas restantes hasta fecha_fin_estimada × sesiones por semana', 'NUMERO', 'SEDE_AREA', '{COORDINADOR}');

-- Calcula y guarda todos los indicadores para una fecha.
CREATE FUNCTION reportes.calcular_indicadores(p_fecha date DEFAULT current_date) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_lunes date := date_trunc('week', p_fecha)::date;
  v_total integer := 0;
  v_filas integer;
BEGIN
  DELETE FROM reportes.valores_indicador WHERE fecha = p_fecha;

  -- Saturación por terapeuta y por sede (semana de p_fecha).
  DROP TABLE IF EXISTS tmp_saturacion;
  CREATE TEMP TABLE tmp_saturacion ON COMMIT DROP AS
  WITH dias AS (
    SELECT d::date AS dia FROM generate_series(v_lunes, v_lunes + 5, interval '1 day') d
  ), jornada AS (
    SELECT j.profesional_id, j.sede_id, sum(extract(epoch FROM j.hora_fin - j.hora_inicio) / 3600.0) AS horas
    FROM agenda.jornadas j
    JOIN dias ON extract(isodow FROM dias.dia) = j.dia_semana AND j.vigencia @> dias.dia
    WHERE NOT EXISTS (SELECT 1 FROM organizacion.feriados f WHERE f.fecha = dias.dia AND (f.sede_id IS NULL OR f.sede_id = j.sede_id))
    GROUP BY j.profesional_id, j.sede_id
  ), pausa AS (
    SELECT p.profesional_id, sum(extract(epoch FROM p.hora_fin - p.hora_inicio) / 3600.0) AS horas
    FROM agenda.pausas p
    JOIN dias ON extract(isodow FROM dias.dia) = p.dia_semana AND daterange(p.vigente_desde, p.vigente_hasta, '[]') @> dias.dia
    WHERE NOT EXISTS (SELECT 1 FROM organizacion.feriados f WHERE f.fecha = dias.dia AND f.sede_id IS NULL)
    GROUP BY p.profesional_id
  ), total_jornada AS (
    SELECT profesional_id, sum(horas) AS horas FROM jornada GROUP BY profesional_id
  ), capacidad AS (
    SELECT j.profesional_id, j.sede_id,
           greatest(j.horas - coalesce(pa.horas, 0) * j.horas / nullif(t.horas, 0), 0) AS horas
    FROM jornada j
    JOIN total_jornada t ON t.profesional_id = j.profesional_id
    LEFT JOIN pausa pa ON pa.profesional_id = j.profesional_id
  ), ocupado AS (
    SELECT s.profesional_id, s.sede_id, sum(extract(epoch FROM s.fin - s.inicio) / 3600.0) AS horas, count(*) AS sesiones
    FROM agenda.sesiones s JOIN organizacion.sedes se ON se.id = s.sede_id
    WHERE s.estado <> 'CANCELADA' AND s.tipo <> 'REUNION'
      AND (s.inicio AT TIME ZONE se.zona_horaria)::date BETWEEN v_lunes AND v_lunes + 5
    GROUP BY s.profesional_id, s.sede_id
  )
  SELECT c.profesional_id, c.sede_id, c.horas AS capacidad, coalesce(o.horas, 0) AS ocupado, coalesce(o.sesiones, 0) AS sesiones
  FROM capacidad c LEFT JOIN ocupado o USING (profesional_id, sede_id);

  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, dimension_id, valor)
  SELECT i.id, p_fecha, t.sede_id, t.profesional_id, round(100 * t.ocupado / nullif(t.capacidad, 0), 2)
  FROM tmp_saturacion t, reportes.indicadores i
  WHERE i.codigo = 'SATURACION_TERAPEUTA' AND t.capacidad > 0;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, t.sede_id, round(100 * sum(t.ocupado) / nullif(sum(t.capacidad), 0), 2)
  FROM tmp_saturacion t, reportes.indicadores i
  WHERE i.codigo = 'SATURACION_SEDE'
  GROUP BY i.id, t.sede_id HAVING sum(t.capacidad) > 0;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, t.sede_id, sum(t.sesiones)
  FROM tmp_saturacion t, reportes.indicadores i
  WHERE i.codigo = 'SESIONES_SEMANA'
  GROUP BY i.id, t.sede_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Pacientes activos por sede y área.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, area_id, valor)
  SELECT i.id, p_fecha, c.sede_id, pg.area_id, count(DISTINCT m.paciente_id)
  FROM matriculas.matriculas m
  JOIN matriculas.contratos c ON c.id = m.contrato_id
  JOIN catalogo.programas pg ON pg.id = m.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'PACIENTES_ACTIVOS' AND m.estado = 'EN_CURSO'
  GROUP BY i.id, c.sede_id, pg.area_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Asistencia de los últimos 30 días.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, area_id, valor)
  SELECT i.id, p_fecha, s.sede_id, pg.area_id,
         round(100.0 * count(*) FILTER (WHERE p.asistencia = 'ASISTIO') / count(*), 2)
  FROM agenda.participantes p
  JOIN agenda.sesiones s ON s.id = p.sesion_id
  JOIN catalogo.programas pg ON pg.id = s.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'ASISTENCIA_30D'
    AND p.asistencia IN ('ASISTIO', 'FALTA', 'FALTA_JUSTIFICADA')
    AND s.inicio >= p_fecha - 30 AND s.inicio < p_fecha + 1
  GROUP BY i.id, s.sede_id, pg.area_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Cancelaciones y reprogramaciones de los últimos 30 días.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, s.sede_id, count(*)
  FROM agenda.participantes p
  JOIN agenda.sesiones s ON s.id = p.sesion_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'CANCELACIONES_30D'
    AND p.asistencia IN ('CANCELADA', 'REPROGRAMADA')
    AND s.inicio >= p_fecha - 30 AND s.inicio < p_fecha + 1
  GROUP BY i.id, s.sede_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Ocupación de grupos activos.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, area_id, valor)
  SELECT i.id, p_fecha, g.sede_id, pg.area_id,
         round(100.0 * avg(
           (SELECT count(*) FROM agenda.grupo_miembros gm
             WHERE gm.grupo_id = g.id AND gm.desde <= p_fecha AND (gm.hasta IS NULL OR gm.hasta >= p_fecha))::numeric
           / g.cupo_maximo), 2)
  FROM agenda.grupos g
  JOIN catalogo.programas pg ON pg.id = g.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'OCUPACION_GRUPOS' AND g.activo
  GROUP BY i.id, g.sede_id, pg.area_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Contratos por vencer en 30 días.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, c.sede_id, count(*)
  FROM matriculas.contratos c CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'CONTRATOS_POR_VENCER' AND c.estado = 'VIGENTE'
    AND c.vigente_hasta BETWEEN p_fecha AND p_fecha + 30
  GROUP BY i.id, c.sede_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Matrículas nuevas del mes.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, area_id, valor)
  SELECT i.id, p_fecha, c.sede_id, pg.area_id, count(*)
  FROM matriculas.matriculas m
  JOIN matriculas.contratos c ON c.id = m.contrato_id
  JOIN catalogo.programas pg ON pg.id = m.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'MATRICULAS_NUEVAS_MES'
    AND m.fecha_inicio >= date_trunc('month', p_fecha)::date AND m.fecha_inicio <= p_fecha
  GROUP BY i.id, c.sede_id, pg.area_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Conversión de valoraciones a matrículas (90 días).
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, v.sede_id,
         round(100.0 * count(*) FILTER (WHERE EXISTS (
                 SELECT 1 FROM matriculas.matriculas m WHERE m.paciente_id = v.paciente_id)) / count(*), 2)
  FROM (
    SELECT DISTINCT s.sede_id, p.paciente_id
    FROM agenda.participantes p JOIN agenda.sesiones s ON s.id = p.sesion_id
    WHERE s.tipo = 'VALORACION' AND p.asistencia = 'ASISTIO'
      AND s.inicio >= p_fecha - 90 AND s.inicio < p_fecha + 1
  ) v CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'CONVERSION_VALORACION_90D'
  GROUP BY i.id, v.sede_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Evaluación promedio de cada terapeuta (90 días).
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, area_id, dimension_id, valor)
  SELECT i.id, p_fecha, pg.area_id, e.profesional_id, round(avg(e.puntaje), 2)
  FROM desempeno.evaluaciones_terapeuta e
  JOIN matriculas.matriculas m ON m.id = e.matricula_id
  JOIN catalogo.programas pg ON pg.id = m.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'EVALUACION_TERAPEUTA_90D'
    AND e.evaluado_en >= p_fecha - 90 AND e.evaluado_en < p_fecha + 1
  GROUP BY i.id, pg.area_id, e.profesional_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Solicitudes de cambio pendientes.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, s.sede_id, count(*)
  FROM agenda.solicitudes_cambio sc
  JOIN agenda.participantes p ON p.id = sc.participante_id
  JOIN agenda.sesiones s ON s.id = p.sesion_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'SOLICITUDES_PENDIENTES' AND sc.estado = 'PENDIENTE'
  GROUP BY i.id, s.sede_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Pacientes activos con demanda alta o muy alta.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, valor)
  SELECT i.id, p_fecha, pa.sede_principal_id, count(*)
  FROM personas.pacientes pa
  JOIN personas.clasificaciones_demanda cd ON cd.paciente_id = pa.id AND cd.vigente
  JOIN personas.niveles_demanda nd ON nd.id = cd.nivel_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'PACIENTES_DEMANDA_ALTA' AND pa.estado = 'ACTIVO' AND nd.peso >= 3
  GROUP BY i.id, pa.sede_principal_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Carga por programa y por especialidad (30 días).
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, dimension_id, valor)
  SELECT i.id, p_fecha, s.sede_id, s.programa_id, count(*)
  FROM agenda.sesiones s CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'CARGA_PROGRAMA_30D' AND s.estado = 'REALIZADA' AND s.programa_id IS NOT NULL
    AND s.inicio >= p_fecha - 30 AND s.inicio < p_fecha + 1
  GROUP BY i.id, s.sede_id, s.programa_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, dimension_id, valor)
  SELECT i.id, p_fecha, s.sede_id, pg.sub_area_requerida_id, count(*)
  FROM agenda.sesiones s
  JOIN catalogo.programas pg ON pg.id = s.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'ESPECIALIDAD_SOLICITADA_30D' AND s.estado = 'REALIZADA'
    AND s.inicio >= p_fecha - 30 AND s.inicio < p_fecha + 1
  GROUP BY i.id, s.sede_id, pg.sub_area_requerida_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Pacientes distintos atendidos por terapeuta (30 días).
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, dimension_id, valor)
  SELECT i.id, p_fecha, s.sede_id, s.profesional_id, count(DISTINCT p.paciente_id)
  FROM agenda.participantes p
  JOIN agenda.sesiones s ON s.id = p.sesion_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'RANKING_TERAPEUTAS_30D' AND p.asistencia = 'ASISTIO'
    AND s.inicio >= p_fecha - 30 AND s.inicio < p_fecha + 1
  GROUP BY i.id, s.sede_id, s.profesional_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  -- Matrículas en riesgo de no completarse.
  INSERT INTO reportes.valores_indicador (indicador_id, fecha, sede_id, area_id, valor)
  SELECT i.id, p_fecha, c.sede_id, pg.area_id, count(*)
  FROM matriculas.v_saldo_sesiones v
  JOIN matriculas.matriculas m ON m.id = v.matricula_id
  JOIN matriculas.contratos c ON c.id = m.contrato_id
  JOIN catalogo.programas pg ON pg.id = m.programa_id
  CROSS JOIN reportes.indicadores i
  WHERE i.codigo = 'RIESGO_NO_COMPLETAR' AND m.estado = 'EN_CURSO'
    AND m.fecha_fin_estimada IS NOT NULL AND pg.sesiones_por_semana IS NOT NULL
    AND (v.sesiones_contratadas - v.sesiones_consumidas)
        > greatest(m.fecha_fin_estimada - p_fecha, 0) / 7.0 * pg.sesiones_por_semana
  GROUP BY i.id, c.sede_id, pg.area_id;
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  RETURN v_total;
END $$;
COMMENT ON FUNCTION reportes.calcular_indicadores IS 'Calcula todos los indicadores para una fecha y los guarda en valores_indicador. Se ejecuta cada noche.';
