-- =============================================================================
-- 050 · Contratos y matrículas
-- Un contrato (NESC-6374) cubre uno o varios programas; cada programa
-- contratado para un paciente es una matrícula.
-- =============================================================================

CREATE SCHEMA matriculas;
COMMENT ON SCHEMA matriculas IS 'Contratos, matrículas y congelamientos.';

CREATE TABLE matriculas.contratos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z]{2,5}-[0-9]{3,6}$'),
  representante_id uuid NOT NULL REFERENCES personas.representantes,
  sede_id          uuid NOT NULL REFERENCES organizacion.sedes,
  tipo             text NOT NULL CHECK (tipo IN ('PLAN', 'CONTADO')),
  valor_total      numeric(10,2) NOT NULL CHECK (valor_total >= 0),
  fecha_firma      date NOT NULL,
  vigente_desde    date NOT NULL,
  vigente_hasta    date NOT NULL,
  estado           text NOT NULL DEFAULT 'VIGENTE' CHECK (estado IN ('VIGENTE', 'VENCIDO', 'CONGELADO', 'FINALIZADO', 'ANULADO')),
  creado_en        timestamptz NOT NULL DEFAULT now(),
  creado_por       uuid,
  actualizado_en   timestamptz NOT NULL DEFAULT now(),
  actualizado_por  uuid,
  CHECK (vigente_hasta >= vigente_desde)
);
COMMENT ON TABLE matriculas.contratos IS 'Contratos firmados por el representante. El portal de familias solo muestra el contrato vigente, sin pagos.';
COMMENT ON COLUMN matriculas.contratos.valor_total IS 'Visible solo para el equipo.';
CREATE TRIGGER contratos_actualizado BEFORE UPDATE ON matriculas.contratos
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER contratos_auditoria AFTER INSERT OR UPDATE OR DELETE ON matriculas.contratos
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();
CREATE INDEX contratos_vencimiento ON matriculas.contratos (estado, vigente_hasta);
CREATE INDEX contratos_representante ON matriculas.contratos (representante_id);

CREATE TABLE matriculas.matriculas (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contrato_id          uuid NOT NULL REFERENCES matriculas.contratos,
  paciente_id          uuid NOT NULL REFERENCES personas.pacientes,
  programa_id          uuid NOT NULL REFERENCES catalogo.programas,
  fase_actual_id       uuid REFERENCES catalogo.programa_fases,
  jornada_preferida    text CHECK (jornada_preferida IN ('MANANA', 'TARDE')),
  fecha_inicio         date NOT NULL,
  fecha_fin_estimada   date,
  sesiones_contratadas smallint NOT NULL CHECK (sesiones_contratadas > 0),
  estado               text NOT NULL DEFAULT 'EN_CURSO' CHECK (estado IN ('EN_CURSO', 'CONGELADA', 'COMPLETADA', 'VENCIDA', 'CANCELADA')),
  origen               text NOT NULL DEFAULT 'PRESENCIAL' CHECK (origen IN ('PRESENCIAL', 'ECOMMERCE')),
  creado_en            timestamptz NOT NULL DEFAULT now(),
  creado_por           uuid,
  actualizado_en       timestamptz NOT NULL DEFAULT now(),
  actualizado_por      uuid,
  CHECK (fecha_fin_estimada IS NULL OR fecha_fin_estimada >= fecha_inicio)
);
COMMENT ON TABLE matriculas.matriculas IS 'Un programa contratado para un paciente. Las sesiones usadas se calculan desde la asistencia (vista v_saldo_sesiones).';
CREATE TRIGGER matriculas_actualizado BEFORE UPDATE ON matriculas.matriculas
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER matriculas_auditoria AFTER INSERT OR UPDATE OR DELETE ON matriculas.matriculas
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();
CREATE INDEX matriculas_paciente ON matriculas.matriculas (paciente_id, estado);
CREATE INDEX matriculas_contrato ON matriculas.matriculas (contrato_id);
CREATE INDEX matriculas_programa ON matriculas.matriculas (programa_id, estado);

CREATE FUNCTION matriculas.tg_validar_matricula() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.fase_actual_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM catalogo.programa_fases f
    WHERE f.id = NEW.fase_actual_id AND f.programa_id = NEW.programa_id
  ) THEN
    RAISE EXCEPTION 'La fase indicada no pertenece al programa de la matrícula.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER matriculas_validar BEFORE INSERT OR UPDATE OF fase_actual_id, programa_id ON matriculas.matriculas
  FOR EACH ROW EXECUTE FUNCTION matriculas.tg_validar_matricula();

CREATE TABLE matriculas.congelamientos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matricula_id uuid NOT NULL REFERENCES matriculas.matriculas ON DELETE CASCADE,
  desde        date NOT NULL,
  hasta        date NOT NULL,
  motivo       text NOT NULL,
  creado_en    timestamptz NOT NULL DEFAULT now(),
  creado_por   uuid,
  CHECK (hasta >= desde)
);
COMMENT ON TABLE matriculas.congelamientos IS 'Pausas de una matrícula (viaje, enfermedad). Durante la pausa no se agendan sesiones.';
CREATE INDEX congelamientos_matricula ON matriculas.congelamientos (matricula_id);
