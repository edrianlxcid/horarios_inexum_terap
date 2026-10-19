-- =============================================================================
-- 170 · Recorrido del paciente (18/10/2026)
-- Flujo del centro:
--   1. Se registra al paciente.
--   2. Valoración inicial: de 1 a 20 sesiones repartidas entre especialidades
--      (terapia ocupacional, psicología infantil, psicología clínica, lenguaje…).
--   3. Programa: terapias específicas, neuroestimulación, etc. (matrículas).
--   4. Valoración final: otra vez de 1 a 20 sesiones.
-- Cada valoración es un "proceso" con sus sesiones previstas por especialidad;
-- la etapa del paciente se calcula a partir de procesos y matrículas.
-- =============================================================================

INSERT INTO comun.parametros (clave, valor, descripcion) VALUES
  ('valoracion.sesiones_minimas', '1',  'Sesiones mínimas de una valoración (inicial o final).'),
  ('valoracion.sesiones_maximas', '20', 'Sesiones máximas de una valoración (inicial o final), sumando todas sus especialidades.');

-- Aísla por empresa una tabla nueva (columna empresa_id + Row Level Security),
-- igual que la migración 130 hizo con las existentes. Para futuras migraciones.
CREATE FUNCTION comun.aislar_por_empresa(p_tabla regclass) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('ALTER TABLE %s ADD COLUMN empresa_id uuid NOT NULL DEFAULT comun.empresa_actual() '
                 'REFERENCES organizacion.empresas', p_tabla);
  EXECUTE format('CREATE INDEX ON %s (empresa_id)', p_tabla);
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', p_tabla);
  EXECUTE format('CREATE POLICY aislamiento_empresa ON %s '
                 'USING (empresa_id = comun.empresa_actual()) WITH CHECK (empresa_id = comun.empresa_actual())', p_tabla);
  EXECUTE format('COMMENT ON COLUMN %s.empresa_id IS %L', p_tabla,
                 'Empresa dueña del registro. Se llena sola con la empresa activa de la sesión.');
END $$;
REVOKE EXECUTE ON FUNCTION comun.aislar_por_empresa(regclass) FROM PUBLIC;
COMMENT ON FUNCTION comun.aislar_por_empresa(regclass) IS 'Solo para migraciones: agrega empresa_id y el aislamiento por empresa a una tabla nueva.';

-- -----------------------------------------------------------------------------
-- Catálogo: qué valoración es cada programa y qué especialidades lo atienden.
-- -----------------------------------------------------------------------------
ALTER TABLE catalogo.programas ADD COLUMN valoracion text CHECK (valoracion IN ('INICIAL', 'FINAL'));
COMMENT ON COLUMN catalogo.programas.valoracion IS 'INICIAL o FINAL si el programa es una valoración; vacío en los programas de terapia.';
UPDATE catalogo.programas pg SET valoracion = 'INICIAL'
FROM catalogo.tipos_programa t WHERE t.id = pg.tipo_programa_id AND t.es_valoracion;

CREATE TABLE catalogo.programa_especialidades (
  programa_id uuid NOT NULL REFERENCES catalogo.programas ON DELETE CASCADE,
  sub_area_id uuid NOT NULL REFERENCES catalogo.sub_areas,
  PRIMARY KEY (programa_id, sub_area_id)
);
COMMENT ON TABLE catalogo.programa_especialidades IS
  'Especialidades que, además de la requerida, pueden atender un programa. Ej.: las valoraciones las hacen terapia ocupacional, psicología o lenguaje.';
DO $$ BEGIN PERFORM comun.aislar_por_empresa('catalogo.programa_especialidades'); END $$;
GRANT DELETE ON catalogo.programa_especialidades TO ismart_app;

CREATE VIEW catalogo.v_especialidades_valoracion WITH (security_invoker = true) AS
SELECT DISTINCT pg.valoracion, x.sub_area_id
FROM catalogo.programas pg
CROSS JOIN LATERAL (SELECT pg.sub_area_requerida_id AS sub_area_id
                    UNION SELECT pe.sub_area_id FROM catalogo.programa_especialidades pe WHERE pe.programa_id = pg.id) x
WHERE pg.activo AND pg.valoracion IS NOT NULL;
COMMENT ON VIEW catalogo.v_especialidades_valoracion IS 'Especialidades que hacen valoraciones iniciales o finales.';
GRANT SELECT ON catalogo.v_especialidades_valoracion TO ismart_app, ismart_reportes;

-- El motor de agenda acepta también esas especialidades (antes: solo la requerida y la de cada fase).
CREATE OR REPLACE FUNCTION agenda.tg_validar_sesion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_zona   text;
  v_ini    timestamp;
  v_fin    timestamp;
  v_dia    smallint;
  v_prog   catalogo.programas%ROWTYPE;
  v_grupo  agenda.grupos%ROWTYPE;
  v_feriado text;
BEGIN
  IF NEW.estado = 'CANCELADA' THEN
    RETURN NEW;
  END IF;
  -- Marcar como realizada una sesión que ya era válida no vuelve a validar el horario.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.estado <> 'CANCELADA'
       AND NEW.inicio = OLD.inicio AND NEW.fin = OLD.fin
       AND NEW.profesional_id = OLD.profesional_id AND NEW.sede_id = OLD.sede_id
       AND NEW.programa_id IS NOT DISTINCT FROM OLD.programa_id
       AND NEW.grupo_id IS NOT DISTINCT FROM OLD.grupo_id
       AND NEW.cupo_maximo = OLD.cupo_maximo AND NEW.tipo = OLD.tipo THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT zona_horaria INTO v_zona FROM organizacion.sedes WHERE id = NEW.sede_id;
  v_ini := NEW.inicio AT TIME ZONE v_zona;
  v_fin := NEW.fin AT TIME ZONE v_zona;
  v_dia := extract(isodow FROM v_ini);

  IF v_ini::date <> v_fin::date THEN
    RAISE EXCEPTION 'Una sesión debe empezar y terminar el mismo día.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_dia = 7 THEN
    RAISE EXCEPTION 'No se agendan sesiones los domingos.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT f.nombre INTO v_feriado FROM organizacion.feriados f
  WHERE f.fecha = v_ini::date AND (f.sede_id IS NULL OR f.sede_id = NEW.sede_id)
  LIMIT 1;
  IF v_feriado IS NOT NULL THEN
    RAISE EXCEPTION 'El % es feriado (%): no se agendan sesiones.', to_char(v_ini, 'DD/MM/YYYY'), v_feriado
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.tipo <> 'REUNION' THEN
    IF NOT EXISTS (
      SELECT 1 FROM agenda.jornadas j
      WHERE j.profesional_id = NEW.profesional_id AND j.sede_id = NEW.sede_id
        AND j.dia_semana = v_dia AND j.vigencia @> v_ini::date
        AND v_ini::time >= j.hora_inicio AND v_fin::time <= j.hora_fin
    ) THEN
      RAISE EXCEPTION 'El horario (% a %) está fuera de la jornada del terapeuta en esta sede.',
        to_char(v_ini, 'TMDy DD/MM HH24:MI'), to_char(v_fin, 'HH24:MI')
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (
      SELECT 1 FROM agenda.pausas p
      WHERE p.profesional_id = NEW.profesional_id AND p.dia_semana = v_dia
        AND daterange(p.vigente_desde, p.vigente_hasta, '[]') @> v_ini::date
        AND v_ini::time < p.hora_fin AND v_fin::time > p.hora_inicio
    ) THEN
      RAISE EXCEPTION 'El horario choca con el almuerzo o las horas administrativas del terapeuta.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM agenda.ausencias a
    WHERE a.profesional_id = NEW.profesional_id AND tstzrange(a.inicio, a.fin) && tstzrange(NEW.inicio, NEW.fin)
  ) THEN
    RAISE EXCEPTION 'El terapeuta está ausente (vacaciones, permiso o capacitación) en ese horario.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.programa_id IS NOT NULL THEN
    SELECT * INTO v_prog FROM catalogo.programas WHERE id = NEW.programa_id;
    IF NEW.cupo_maximo > v_prog.cupo_maximo THEN
      RAISE EXCEPTION 'El cupo de la sesión (%) supera el del programa "%" (%).', NEW.cupo_maximo, v_prog.nombre, v_prog.cupo_maximo
        USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM personas.profesional_sub_areas psa
      WHERE psa.profesional_id = NEW.profesional_id
        AND (psa.sub_area_id = v_prog.sub_area_requerida_id
             OR psa.sub_area_id IN (SELECT f.sub_area_id FROM catalogo.programa_fases f
                                    WHERE f.programa_id = v_prog.id AND f.sub_area_id IS NOT NULL)
             OR psa.sub_area_id IN (SELECT pe.sub_area_id FROM catalogo.programa_especialidades pe
                                    WHERE pe.programa_id = v_prog.id))
    ) THEN
      RAISE EXCEPTION 'El terapeuta no está habilitado en la especialidad del programa "%".', v_prog.nombre
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.grupo_id IS NOT NULL THEN
    SELECT * INTO v_grupo FROM agenda.grupos WHERE id = NEW.grupo_id;
    IF NEW.programa_id IS DISTINCT FROM v_grupo.programa_id THEN
      RAISE EXCEPTION 'La sesión y el grupo % deben ser del mismo programa.', v_grupo.codigo
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.cupo_maximo > v_grupo.cupo_maximo THEN
      RAISE EXCEPTION 'El cupo de la sesión supera el del grupo %.', v_grupo.codigo
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END $$;

-- -----------------------------------------------------------------------------
-- Procesos de valoración (inicial y final) y sus sesiones previstas.
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.procesos_valoracion (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id             uuid NOT NULL REFERENCES personas.pacientes,
  tipo                    text NOT NULL CHECK (tipo IN ('INICIAL', 'FINAL')),
  matricula_id            uuid REFERENCES matriculas.matriculas,
  estado                  text NOT NULL DEFAULT 'EN_CURSO' CHECK (estado IN ('EN_CURSO', 'COMPLETADA', 'CANCELADA')),
  resultado               text,
  programa_recomendado_id uuid REFERENCES catalogo.programas,
  conclusion              text,
  abierto_en              timestamptz NOT NULL DEFAULT now(),
  abierto_por             uuid REFERENCES seguridad.usuarios,
  cerrado_en              timestamptz,
  cerrado_por             uuid REFERENCES seguridad.usuarios,
  actualizado_en          timestamptz NOT NULL DEFAULT now(),
  CHECK ((estado = 'EN_CURSO') = (cerrado_en IS NULL)),
  CHECK (estado <> 'COMPLETADA' OR resultado IS NOT NULL),
  CHECK (resultado IS NULL
         OR (tipo = 'INICIAL' AND resultado IN ('INGRESA_A_PROGRAMA', 'NO_REQUIERE'))
         OR (tipo = 'FINAL' AND resultado IN ('ALTA', 'CONTINUA', 'DERIVADO')))
);
COMMENT ON TABLE agenda.procesos_valoracion IS
  'Valoración inicial (antes del programa) o final (al terminarlo) de un paciente, con su resultado.';
COMMENT ON COLUMN agenda.procesos_valoracion.matricula_id IS 'Valoración final: el programa que cierra.';
COMMENT ON COLUMN agenda.procesos_valoracion.resultado IS
  'INICIAL: INGRESA_A_PROGRAMA o NO_REQUIERE. FINAL: ALTA, CONTINUA (sigue con otro programa) o DERIVADO.';
DO $$ BEGIN PERFORM comun.aislar_por_empresa('agenda.procesos_valoracion'); END $$;
CREATE UNIQUE INDEX procesos_uno_en_curso ON agenda.procesos_valoracion (paciente_id, tipo) WHERE estado = 'EN_CURSO';
CREATE INDEX procesos_paciente ON agenda.procesos_valoracion (paciente_id);
CREATE TRIGGER procesos_actualizado BEFORE UPDATE ON agenda.procesos_valoracion
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER procesos_auditoria AFTER INSERT OR UPDATE OR DELETE ON agenda.procesos_valoracion
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();
-- Indicadores: pueden contar procesos, pero no leer la conclusión.
REVOKE SELECT ON agenda.procesos_valoracion FROM ismart_reportes;
GRANT SELECT (id, empresa_id, paciente_id, tipo, matricula_id, estado, resultado, programa_recomendado_id, abierto_en, cerrado_en)
  ON agenda.procesos_valoracion TO ismart_reportes;

CREATE TABLE agenda.proceso_especialidades (
  proceso_id  uuid NOT NULL REFERENCES agenda.procesos_valoracion ON DELETE CASCADE,
  sub_area_id uuid NOT NULL REFERENCES catalogo.sub_areas,
  sesiones    smallint NOT NULL CHECK (sesiones >= 1),
  PRIMARY KEY (proceso_id, sub_area_id)
);
COMMENT ON TABLE agenda.proceso_especialidades IS
  'Sesiones previstas de una valoración por especialidad (ej.: 2 de terapia ocupacional y 3 de psicología).';
DO $$ BEGIN PERFORM comun.aislar_por_empresa('agenda.proceso_especialidades'); END $$;
GRANT DELETE ON agenda.proceso_especialidades TO ismart_app;

-- El total previsto de una valoración no pasa del máximo (parámetro) ni baja
-- de lo que ya se agendó en esa especialidad.
CREATE FUNCTION agenda.tg_validar_plan_valoracion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_max   smallint := (SELECT (valor #>> '{}')::smallint FROM comun.parametros WHERE clave = 'valoracion.sesiones_maximas');
  v_total int;
  v_usadas int;
BEGIN
  SELECT coalesce(sum(sesiones), 0) + NEW.sesiones INTO v_total
  FROM agenda.proceso_especialidades
  WHERE proceso_id = NEW.proceso_id AND sub_area_id <> NEW.sub_area_id;
  IF v_total > coalesce(v_max, 20) THEN
    RAISE EXCEPTION 'Una valoración tiene como máximo % sesiones (quedarían %).', coalesce(v_max, 20), v_total
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT count(*) INTO v_usadas FROM agenda.participantes x
  WHERE x.proceso_valoracion_id = NEW.proceso_id AND x.valoracion_especialidad_id = NEW.sub_area_id
    AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA');
  IF NEW.sesiones < v_usadas THEN
    RAISE EXCEPTION 'Ya hay % sesiones agendadas o realizadas de esa especialidad: no se puede prever menos.', v_usadas
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- Cada sesión de valoración pertenece a un proceso y a una de sus especialidades.
ALTER TABLE agenda.participantes
  ADD COLUMN proceso_valoracion_id     uuid REFERENCES agenda.procesos_valoracion,
  ADD COLUMN valoracion_especialidad_id uuid REFERENCES catalogo.sub_areas,
  ADD CONSTRAINT participantes_valoracion_completa
    CHECK ((proceso_valoracion_id IS NULL) = (valoracion_especialidad_id IS NULL));
COMMENT ON COLUMN agenda.participantes.proceso_valoracion_id IS 'Sesión de valoración: el proceso (inicial o final) al que pertenece.';
COMMENT ON COLUMN agenda.participantes.valoracion_especialidad_id IS 'Sesión de valoración: la especialidad que valora en esta sesión.';
CREATE INDEX participantes_proceso ON agenda.participantes (proceso_valoracion_id) WHERE proceso_valoracion_id IS NOT NULL;

CREATE TRIGGER proceso_especialidades_validar BEFORE INSERT OR UPDATE ON agenda.proceso_especialidades
  FOR EACH ROW EXECUTE FUNCTION agenda.tg_validar_plan_valoracion();

CREATE FUNCTION agenda.tg_validar_sesion_valoracion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_proceso  agenda.procesos_valoracion%ROWTYPE;
  v_sesion   agenda.sesiones%ROWTYPE;
  v_prevista smallint;
  v_usadas   int;
BEGIN
  IF NEW.proceso_valoracion_id IS NULL OR NEW.asistencia IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA') THEN
    RETURN NEW;
  END IF;
  -- Solo se valida al agregar la sesión o al reactivarla.
  IF TG_OP = 'UPDATE' AND OLD.proceso_valoracion_id IS NOT DISTINCT FROM NEW.proceso_valoracion_id
     AND OLD.valoracion_especialidad_id IS NOT DISTINCT FROM NEW.valoracion_especialidad_id
     AND OLD.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA') THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_proceso FROM agenda.procesos_valoracion WHERE id = NEW.proceso_valoracion_id FOR UPDATE;
  SELECT * INTO v_sesion FROM agenda.sesiones WHERE id = NEW.sesion_id;
  IF v_proceso.paciente_id <> NEW.paciente_id THEN
    RAISE EXCEPTION 'Esa valoración es de otro paciente.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_sesion.tipo <> 'VALORACION' THEN
    RAISE EXCEPTION 'Solo las sesiones de valoración pertenecen a un proceso de valoración.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_proceso.estado <> 'EN_CURSO' THEN
    RAISE EXCEPTION 'Esa valoración ya está cerrada.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM personas.profesional_sub_areas psa
                 WHERE psa.profesional_id = v_sesion.profesional_id AND psa.sub_area_id = NEW.valoracion_especialidad_id) THEN
    RAISE EXCEPTION 'El profesional no es de la especialidad que se va a valorar.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT sesiones INTO v_prevista FROM agenda.proceso_especialidades
  WHERE proceso_id = NEW.proceso_valoracion_id AND sub_area_id = NEW.valoracion_especialidad_id;
  IF v_prevista IS NULL THEN
    RAISE EXCEPTION 'Esa especialidad no está prevista en la valoración.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT count(*) INTO v_usadas FROM agenda.participantes x
  WHERE x.proceso_valoracion_id = NEW.proceso_valoracion_id AND x.valoracion_especialidad_id = NEW.valoracion_especialidad_id
    AND x.id <> NEW.id AND x.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA');
  IF v_usadas >= v_prevista THEN
    RAISE EXCEPTION 'Ya están agendadas todas las sesiones previstas de esa especialidad (%). Amplía la valoración si hace falta.', v_prevista
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER participantes_validar_valoracion BEFORE INSERT OR UPDATE ON agenda.participantes
  FOR EACH ROW EXECUTE FUNCTION agenda.tg_validar_sesion_valoracion();

-- -----------------------------------------------------------------------------
-- Etapa del paciente en su recorrido (se calcula, no se guarda).
-- -----------------------------------------------------------------------------
CREATE FUNCTION agenda.etapa_paciente(p_paciente uuid) RETURNS text
LANGUAGE sql STABLE AS $$
  WITH pr AS (
    SELECT tipo, estado, resultado, cerrado_en FROM agenda.procesos_valoracion
    WHERE paciente_id = p_paciente AND estado <> 'CANCELADA'
  ), m AS (
    SELECT mt.estado, mt.sesiones_contratadas, mt.fecha_inicio,
           (SELECT count(*) FROM agenda.participantes x
            WHERE x.matricula_id = mt.id AND x.asistencia IN ('ASISTIO', 'FALTA')) AS consumidas
    FROM matriculas.matriculas mt
    WHERE mt.paciente_id = p_paciente AND mt.estado <> 'CANCELADA'
  )
  SELECT CASE
    WHEN (SELECT estado FROM personas.pacientes WHERE id = p_paciente) = 'RETIRADO' THEN 'RETIRADO'
    WHEN EXISTS (SELECT 1 FROM pr WHERE tipo = 'FINAL' AND estado = 'EN_CURSO') THEN 'VALORACION_FINAL'
    WHEN EXISTS (SELECT 1 FROM pr WHERE tipo = 'INICIAL' AND estado = 'EN_CURSO') THEN 'VALORACION_INICIAL'
    WHEN EXISTS (SELECT 1 FROM m WHERE estado IN ('EN_CURSO', 'CONGELADA') AND consumidas < sesiones_contratadas) THEN 'EN_PROGRAMA'
    -- Terminó su programa: depende del resultado de la valoración final posterior.
    WHEN EXISTS (SELECT 1 FROM m) THEN
      CASE (SELECT resultado FROM pr WHERE tipo = 'FINAL' AND estado = 'COMPLETADA'
            AND cerrado_en::date >= (SELECT max(fecha_inicio) FROM m) ORDER BY cerrado_en DESC LIMIT 1)
        WHEN 'CONTINUA' THEN 'POR_INGRESAR'
        WHEN 'ALTA' THEN 'FINALIZADO'
        WHEN 'DERIVADO' THEN 'FINALIZADO'
        ELSE 'POR_VALORACION_FINAL'
      END
    WHEN EXISTS (SELECT 1 FROM pr WHERE tipo = 'INICIAL' AND estado = 'COMPLETADA' AND resultado = 'NO_REQUIERE') THEN 'FINALIZADO'
    WHEN EXISTS (SELECT 1 FROM pr WHERE tipo = 'INICIAL' AND estado = 'COMPLETADA') THEN 'POR_INGRESAR'
    ELSE 'POR_VALORAR'
  END
$$;
COMMENT ON FUNCTION agenda.etapa_paciente(uuid) IS
  'POR_VALORAR, VALORACION_INICIAL, POR_INGRESAR (valorado y sin programa en curso), EN_PROGRAMA, POR_VALORACION_FINAL, '
  'VALORACION_FINAL, FINALIZADO (alta) o RETIRADO.';
GRANT EXECUTE ON FUNCTION agenda.etapa_paciente(uuid) TO ismart_app;
