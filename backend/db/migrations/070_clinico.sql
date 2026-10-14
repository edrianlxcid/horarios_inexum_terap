-- =============================================================================
-- 070 · Seguimiento clínico
-- Valoraciones, notas de sesión, objetivos, avances y tareas para casa.
-- Esquema con permisos aparte: reportes no puede leerlo.
-- =============================================================================

CREATE SCHEMA clinico;
COMMENT ON SCHEMA clinico IS 'Datos clínicos: valoraciones, notas de sesión, objetivos y tareas. Contenido sensible cifrado.';

CREATE TABLE clinico.valoraciones (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  participante_id         uuid NOT NULL UNIQUE REFERENCES agenda.participantes,
  profesional_id          uuid NOT NULL REFERENCES personas.profesionales,
  instrumento             text,
  resultados              bytea,
  conclusion              text,
  programa_recomendado_id uuid REFERENCES catalogo.programas,
  creado_en               timestamptz NOT NULL DEFAULT now(),
  creado_por              uuid,
  actualizado_en          timestamptz NOT NULL DEFAULT now(),
  actualizado_por         uuid
);
COMMENT ON TABLE clinico.valoraciones IS 'Resultado de cada sesión de valoración y el programa recomendado.';
COMMENT ON COLUMN clinico.valoraciones.resultados IS 'Resultados detallados, cifrados.';
CREATE TRIGGER valoraciones_actualizado BEFORE UPDATE ON clinico.valoraciones
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER valoraciones_auditoria AFTER INSERT OR UPDATE OR DELETE ON clinico.valoraciones
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar('resultados');

CREATE TABLE clinico.plantillas_nota (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  programa_id uuid REFERENCES catalogo.programas,
  nombre      text NOT NULL,
  campos      jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(campos) = 'array'),
  activo      boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE clinico.plantillas_nota IS 'Plantillas para escribir notas de sesión rápido. Sin programa = plantilla general.';

CREATE TABLE clinico.notas_sesion (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  participante_id uuid NOT NULL UNIQUE REFERENCES agenda.participantes,
  profesional_id  uuid NOT NULL REFERENCES personas.profesionales,
  plantilla_id    uuid REFERENCES clinico.plantillas_nota,
  contenido       bytea NOT NULL,
  resumen_familia text,
  firmada_en      timestamptz,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  actualizado_en  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE clinico.notas_sesion IS 'Nota del terapeuta por cada asistencia. Una vez firmada no se edita: las correcciones van como anexo.';
COMMENT ON COLUMN clinico.notas_sesion.contenido IS 'Nota completa, cifrada. Solo la ve el equipo clínico autorizado.';
COMMENT ON COLUMN clinico.notas_sesion.resumen_familia IS 'Texto breve que ve la familia en su portal.';
CREATE INDEX notas_profesional ON clinico.notas_sesion (profesional_id, creado_en);
CREATE TRIGGER notas_actualizado BEFORE UPDATE ON clinico.notas_sesion
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER notas_auditoria AFTER INSERT OR UPDATE OR DELETE ON clinico.notas_sesion
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar('contenido');

-- Regla 9: una nota firmada no se edita ni se elimina.
CREATE FUNCTION clinico.tg_nota_firmada() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.firmada_en IS NOT NULL THEN
    RAISE EXCEPTION 'La nota ya fue firmada el %: agregue una corrección como anexo.', to_char(OLD.firmada_en, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER notas_firmadas_inmutables BEFORE UPDATE OR DELETE ON clinico.notas_sesion
  FOR EACH ROW EXECUTE FUNCTION clinico.tg_nota_firmada();

CREATE TABLE clinico.notas_anexos (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nota_id        uuid NOT NULL REFERENCES clinico.notas_sesion,
  profesional_id uuid NOT NULL REFERENCES personas.profesionales,
  contenido      bytea NOT NULL,
  creado_en      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE clinico.notas_anexos IS 'Correcciones a notas ya firmadas, con fecha y autor.';
CREATE INDEX notas_anexos_nota ON clinico.notas_anexos (nota_id);

CREATE TABLE clinico.objetivos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matricula_id uuid NOT NULL REFERENCES matriculas.matriculas,
  descripcion  text NOT NULL,
  estado       text NOT NULL DEFAULT 'EN_PROCESO' CHECK (estado IN ('EN_PROCESO', 'LOGRADO', 'SUSPENDIDO')),
  fecha_inicio date NOT NULL,
  fecha_logro  date,
  creado_en    timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  CHECK ((estado = 'LOGRADO') = (fecha_logro IS NOT NULL))
);
COMMENT ON TABLE clinico.objetivos IS 'Objetivos terapéuticos de cada matrícula. Base del progreso que ve la familia.';
CREATE INDEX objetivos_matricula ON clinico.objetivos (matricula_id);
CREATE TRIGGER objetivos_actualizado BEFORE UPDATE ON clinico.objetivos
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();

CREATE TABLE clinico.avances_objetivo (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  objetivo_id   uuid NOT NULL REFERENCES clinico.objetivos ON DELETE CASCADE,
  nota_id       uuid REFERENCES clinico.notas_sesion,
  nivel         smallint NOT NULL CHECK (nivel BETWEEN 1 AND 5),
  comentario    text,
  registrado_en timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE clinico.avances_objetivo IS 'Avance de un objetivo en una sesión, del 1 (inicio) al 5 (logrado).';
CREATE INDEX avances_objetivo_fecha ON clinico.avances_objetivo (objetivo_id, registrado_en);

CREATE TABLE clinico.tareas_casa (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id        uuid NOT NULL REFERENCES personas.pacientes,
  profesional_id     uuid NOT NULL REFERENCES personas.profesionales,
  titulo             text NOT NULL,
  descripcion        text,
  fecha_asignada     date NOT NULL DEFAULT current_date,
  fecha_limite       date,
  completada_en      timestamptz,
  comentario_familia text,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  CHECK (fecha_limite IS NULL OR fecha_limite >= fecha_asignada)
);
COMMENT ON TABLE clinico.tareas_casa IS 'Ejercicios para casa que deja el terapeuta y que la familia marca como hechos.';
CREATE INDEX tareas_paciente ON clinico.tareas_casa (paciente_id, fecha_asignada);
