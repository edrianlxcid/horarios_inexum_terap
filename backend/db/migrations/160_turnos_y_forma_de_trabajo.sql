-- =============================================================================
-- 160 · Turnos por especialidad y forma de trabajo actual (18/10/2026)
-- Tomado de los horarios que hoy lleva Coordinación en hojas de cálculo:
--  - Terapia de lenguaje atiende en turnos de 45 minutos seguidos.
--  - Neuro atiende cada hora: 45 minutos de sesión y 15 de descanso.
--  - Valoraciones: un paciente por hora.
-- El turno lo marca la especialidad principal del profesional; la duración
-- real de la sesión la marca el programa (catalogo.programas.duracion_sesion_min).
-- =============================================================================

ALTER TABLE catalogo.sub_areas
  ADD COLUMN minutos_turno smallint NOT NULL DEFAULT 60 CHECK (minutos_turno BETWEEN 15 AND 240);
COMMENT ON COLUMN catalogo.sub_areas.minutos_turno IS
  'Cada cuántos minutos empieza un turno en la agenda de quien tiene esta especialidad como principal (60 = cada hora; 45 = seguidos).';

-- Nota de coordinación en cada cita, como la columna OBSERVACIÓN de los
-- horarios: "desde el 12 de octubre", "solo por hoy", "no mover", "rotativo".
ALTER TABLE agenda.participantes ADD COLUMN observacion text;
COMMENT ON COLUMN agenda.participantes.observacion IS 'Nota de coordinación para esta cita (no es una nota clínica).';

-- Códigos de contrato como se escriben hoy: "NESC 1234" (también vale "NESC-1234").
ALTER TABLE matriculas.contratos DROP CONSTRAINT contratos_codigo_check;
ALTER TABLE matriculas.contratos ADD CONSTRAINT contratos_codigo_check CHECK (codigo ~ '^[A-Z]{2,5}[ -][0-9]{3,6}$');

-- Jornada rotativa: el paciente alterna mañana y tarde.
ALTER TABLE matriculas.matriculas DROP CONSTRAINT matriculas_jornada_preferida_check;
ALTER TABLE matriculas.matriculas ADD CONSTRAINT matriculas_jornada_preferida_check
  CHECK (jornada_preferida IN ('MANANA', 'TARDE', 'ROTATIVO'));

-- Minutos de turno de un profesional: los de su especialidad principal.
CREATE FUNCTION agenda.minutos_turno(p_profesional uuid) RETURNS smallint
LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT sa.minutos_turno
                   FROM personas.profesional_sub_areas psa JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id
                   WHERE psa.profesional_id = p_profesional
                   ORDER BY psa.es_principal DESC, sa.minutos_turno
                   LIMIT 1), 60)::smallint
$$;
COMMENT ON FUNCTION agenda.minutos_turno(uuid) IS 'Duración del turno en la agenda del profesional (según su especialidad principal).';
GRANT EXECUTE ON FUNCTION agenda.minutos_turno(uuid) TO ismart_app, ismart_reportes;
