-- =============================================================================
-- 080 · Desempeño (reunión del 5/10/2026)
-- La familia evalúa al terapeuta antes de terminar el programa (por defecto en
-- la penúltima sesión). El promedio de esas evaluaciones define el bono.
-- Escala, niveles y montos son paramétricos.
-- =============================================================================

CREATE SCHEMA desempeno;
COMMENT ON SCHEMA desempeno IS 'Evaluación del terapeuta por la familia y bono de desempeño.';

CREATE TABLE desempeno.escala_evaluacion (
  valor       smallint PRIMARY KEY CHECK (valor BETWEEN 1 AND 10),
  etiqueta    text NOT NULL,
  descripcion text
);
COMMENT ON TABLE desempeno.escala_evaluacion IS 'Escala de evaluación. Paramétrica: queda por validar si se usa 1 a 5 u otra.';

INSERT INTO desempeno.escala_evaluacion (valor, etiqueta) VALUES
  (1, 'Muy mala'), (2, 'Regular'), (3, 'Buena'), (4, 'Muy buena'), (5, 'Excelente');

CREATE TABLE desempeno.evaluaciones_terapeuta (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matricula_id     uuid NOT NULL REFERENCES matriculas.matriculas,
  profesional_id   uuid NOT NULL REFERENCES personas.profesionales,
  representante_id uuid NOT NULL REFERENCES personas.representantes,
  puntaje          smallint NOT NULL REFERENCES desempeno.escala_evaluacion (valor),
  comentario       text,
  evaluado_en      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (matricula_id, profesional_id)
);
COMMENT ON TABLE desempeno.evaluaciones_terapeuta IS 'Evaluación obligatoria de la familia al terapeuta, una vez por matrícula y terapeuta.';
CREATE INDEX evaluaciones_profesional ON desempeno.evaluaciones_terapeuta (profesional_id, evaluado_en);
CREATE TRIGGER evaluaciones_auditoria AFTER INSERT OR UPDATE OR DELETE ON desempeno.evaluaciones_terapeuta
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();

CREATE FUNCTION desempeno.tg_validar_evaluacion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_contratadas  smallint;
  v_antes        smallint;
  v_consumidas   bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM matriculas.matriculas m
    JOIN personas.paciente_representantes pr ON pr.paciente_id = m.paciente_id
    WHERE m.id = NEW.matricula_id AND pr.representante_id = NEW.representante_id
  ) THEN
    RAISE EXCEPTION 'Solo un representante del paciente puede evaluar al terapeuta.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM agenda.participantes p JOIN agenda.sesiones s ON s.id = p.sesion_id
    WHERE p.matricula_id = NEW.matricula_id AND s.profesional_id = NEW.profesional_id AND p.asistencia = 'ASISTIO'
  ) THEN
    RAISE EXCEPTION 'El terapeuta no ha atendido sesiones de esta matrícula.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT m.sesiones_contratadas, pg.sesiones_antes_evaluacion INTO v_contratadas, v_antes
  FROM matriculas.matriculas m JOIN catalogo.programas pg ON pg.id = m.programa_id
  WHERE m.id = NEW.matricula_id;
  SELECT sesiones_consumidas INTO v_consumidas FROM matriculas.v_saldo_sesiones WHERE matricula_id = NEW.matricula_id;
  IF v_consumidas < v_contratadas - v_antes THEN
    RAISE EXCEPTION 'La evaluación se habilita al llegar a la sesión % de %.', v_contratadas - v_antes, v_contratadas
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER evaluaciones_validar BEFORE INSERT ON desempeno.evaluaciones_terapeuta
  FOR EACH ROW EXECUTE FUNCTION desempeno.tg_validar_evaluacion();

-- Matrículas que llegaron al punto de evaluación y aún no evalúan a su terapeuta
-- principal. El portal de familias bloquea los resultados hasta que evalúen.
CREATE VIEW desempeno.v_evaluaciones_pendientes AS
WITH principal AS (
  SELECT DISTINCT ON (p.matricula_id) p.matricula_id, s.profesional_id
  FROM agenda.participantes p JOIN agenda.sesiones s ON s.id = p.sesion_id
  WHERE p.matricula_id IS NOT NULL AND p.asistencia = 'ASISTIO'
  GROUP BY p.matricula_id, s.profesional_id
  ORDER BY p.matricula_id, count(*) DESC
)
SELECT v.matricula_id, v.paciente_id, pr.profesional_id, v.sesiones_contratadas, v.sesiones_consumidas
FROM matriculas.v_saldo_sesiones v
JOIN catalogo.programas pg ON pg.id = v.programa_id
JOIN principal pr ON pr.matricula_id = v.matricula_id
WHERE v.estado IN ('EN_CURSO', 'COMPLETADA')
  AND v.sesiones_consumidas >= v.sesiones_contratadas - pg.sesiones_antes_evaluacion
  AND NOT EXISTS (SELECT 1 FROM desempeno.evaluaciones_terapeuta e
                  WHERE e.matricula_id = v.matricula_id AND e.profesional_id = pr.profesional_id);
COMMENT ON VIEW desempeno.v_evaluaciones_pendientes IS 'Familias que deben evaluar a su terapeuta antes de ver los resultados.';

CREATE TABLE desempeno.politicas_bono (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre              text NOT NULL,
  area_id             uuid REFERENCES catalogo.areas,
  monto_base          numeric(10,2) NOT NULL CHECK (monto_base >= 0),
  periodicidad        text NOT NULL DEFAULT 'MENSUAL' CHECK (periodicidad IN ('MENSUAL', 'TRIMESTRAL')),
  minimo_evaluaciones smallint NOT NULL DEFAULT 3 CHECK (minimo_evaluaciones >= 1),
  vigente_desde       date NOT NULL,
  vigente_hasta       date,
  activo              boolean NOT NULL DEFAULT true,
  CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);
COMMENT ON TABLE desempeno.politicas_bono IS 'Bono de desempeño: monto base y cada cuánto se calcula. Sin área = aplica a todas.';

CREATE TABLE desempeno.bono_niveles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  politica_id uuid NOT NULL REFERENCES desempeno.politicas_bono ON DELETE CASCADE,
  puntaje_min numeric(4,2) NOT NULL CHECK (puntaje_min >= 0),
  porcentaje  numeric(5,2) NOT NULL CHECK (porcentaje BETWEEN 0 AND 100),
  UNIQUE (politica_id, puntaje_min)
);
COMMENT ON TABLE desempeno.bono_niveles IS 'Tramos del bono: desde qué promedio se paga qué porcentaje del monto base.';

CREATE TABLE desempeno.bonos_calculados (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  politica_id    uuid NOT NULL REFERENCES desempeno.politicas_bono,
  profesional_id uuid NOT NULL REFERENCES personas.profesionales,
  periodo_inicio date NOT NULL,
  periodo_fin    date NOT NULL,
  evaluaciones   integer NOT NULL,
  promedio       numeric(4,2),
  porcentaje     numeric(5,2) NOT NULL,
  monto          numeric(10,2) NOT NULL,
  monto_posible  numeric(10,2) NOT NULL,
  calculado_en   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (politica_id, profesional_id, periodo_inicio)
);
COMMENT ON TABLE desempeno.bonos_calculados IS 'Resultado del cálculo del bono por terapeuta y periodo. Muestra lo ganado y lo que pudo ganar.';

-- Calcula (o recalcula) el bono de un periodo para todos los terapeutas.
CREATE FUNCTION desempeno.calcular_bonos(p_politica uuid, p_inicio date, p_fin date) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_pol  desempeno.politicas_bono%ROWTYPE;
  v_filas integer;
BEGIN
  SELECT * INTO v_pol FROM desempeno.politicas_bono WHERE id = p_politica;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la política de bono %.', p_politica;
  END IF;

  WITH promedios AS (
    SELECT e.profesional_id, count(*) AS evaluaciones, round(avg(e.puntaje), 2) AS promedio
    FROM desempeno.evaluaciones_terapeuta e
    JOIN matriculas.matriculas m ON m.id = e.matricula_id
    JOIN catalogo.programas pg ON pg.id = m.programa_id
    WHERE e.evaluado_en >= p_inicio AND e.evaluado_en < p_fin + 1
      AND (v_pol.area_id IS NULL OR pg.area_id = v_pol.area_id)
    GROUP BY e.profesional_id
  ), tramos AS (
    SELECT pr.*,
           CASE WHEN pr.evaluaciones < v_pol.minimo_evaluaciones THEN 0
                ELSE coalesce((SELECT b.porcentaje FROM desempeno.bono_niveles b
                               WHERE b.politica_id = v_pol.id AND b.puntaje_min <= pr.promedio
                               ORDER BY b.puntaje_min DESC LIMIT 1), 0)
           END AS porcentaje
    FROM promedios pr
  )
  INSERT INTO desempeno.bonos_calculados
    (politica_id, profesional_id, periodo_inicio, periodo_fin, evaluaciones, promedio, porcentaje, monto, monto_posible)
  SELECT v_pol.id, t.profesional_id, p_inicio, p_fin, t.evaluaciones, t.promedio, t.porcentaje,
         round(v_pol.monto_base * t.porcentaje / 100, 2), v_pol.monto_base
  FROM tramos t
  ON CONFLICT (politica_id, profesional_id, periodo_inicio) DO UPDATE
    SET periodo_fin = EXCLUDED.periodo_fin, evaluaciones = EXCLUDED.evaluaciones,
        promedio = EXCLUDED.promedio, porcentaje = EXCLUDED.porcentaje,
        monto = EXCLUDED.monto, monto_posible = EXCLUDED.monto_posible, calculado_en = now();
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas;
END $$;
COMMENT ON FUNCTION desempeno.calcular_bonos IS 'Calcula el bono de cada terapeuta según el promedio de sus evaluaciones en el periodo.';
