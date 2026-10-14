-- =============================================================================
-- 020 · Catálogo de programas
-- Áreas, especialidades, tipos de programa y programas con sus reglas.
-- Cada programa guarda sus propias reglas: agregar uno nuevo no requiere programar.
-- =============================================================================

CREATE SCHEMA catalogo;
COMMENT ON SCHEMA catalogo IS 'Áreas, especialidades, tipos de programa, programas y fases.';

CREATE TABLE catalogo.areas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo         text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z_]+$'),
  nombre         text NOT NULL,
  activo         boolean NOT NULL DEFAULT true,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE catalogo.areas IS 'Áreas de negocio (Neuro, Inglés/Estimulación). Los coordinadores e informes se separan por área.';
CREATE TRIGGER areas_actualizado BEFORE UPDATE ON catalogo.areas
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();

CREATE TABLE catalogo.sub_areas (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  area_id uuid NOT NULL REFERENCES catalogo.areas,
  codigo  text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z_]+$'),
  nombre  text NOT NULL,
  activo  boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE catalogo.sub_areas IS 'Especialidades. Un terapeuta solo puede atender programas de las especialidades en las que está habilitado.';

CREATE TABLE catalogo.tipos_programa (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo        text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z_]+$'),
  nombre        text NOT NULL,
  descripcion   text,
  patron        text NOT NULL CHECK (patron IN ('SEMANAL_FIJO', 'BLOQUE_INTENSIVO', 'LIBRE', 'UNICO')),
  es_valoracion boolean NOT NULL DEFAULT false
);
COMMENT ON TABLE catalogo.tipos_programa IS 'Cómo se agenda un programa: días fijos por semana, bloque intensivo, libre o cita única.';

CREATE TABLE catalogo.programas (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  area_id                   uuid NOT NULL REFERENCES catalogo.areas,
  tipo_programa_id          uuid NOT NULL REFERENCES catalogo.tipos_programa,
  sub_area_requerida_id     uuid NOT NULL REFERENCES catalogo.sub_areas,
  codigo                    text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z0-9_]+$'),
  nombre                    text NOT NULL,
  total_sesiones            smallint NOT NULL CHECK (total_sesiones > 0),
  duracion_meses            smallint CHECK (duracion_meses > 0),
  duracion_sesion_min       smallint NOT NULL DEFAULT 60 CHECK (duracion_sesion_min BETWEEN 15 AND 240),
  sesiones_por_semana       smallint CHECK (sesiones_por_semana BETWEEN 1 AND 6),
  modalidad                 text NOT NULL CHECK (modalidad IN ('INDIVIDUAL', 'GRUPAL', 'MIXTA')),
  modalidad_entrega         text NOT NULL DEFAULT 'PRESENCIAL' CHECK (modalidad_entrega IN ('PRESENCIAL', 'ONLINE')),
  cupo_maximo               smallint NOT NULL DEFAULT 1 CHECK (cupo_maximo >= 1),
  requiere_valoracion       boolean NOT NULL DEFAULT true,
  sesiones_antes_evaluacion smallint NOT NULL DEFAULT 1 CHECK (sesiones_antes_evaluacion >= 0),
  precio_referencial        numeric(10,2) CHECK (precio_referencial >= 0),
  reglas_extra              jsonb NOT NULL DEFAULT '{}'::jsonb,
  activo                    boolean NOT NULL DEFAULT true,
  creado_en                 timestamptz NOT NULL DEFAULT now(),
  creado_por                uuid,
  actualizado_en            timestamptz NOT NULL DEFAULT now(),
  actualizado_por           uuid,
  CONSTRAINT programas_individual_cupo_1 CHECK (modalidad <> 'INDIVIDUAL' OR cupo_maximo = 1),
  CONSTRAINT programas_evaluacion_dentro CHECK (sesiones_antes_evaluacion < total_sesiones)
);
COMMENT ON TABLE catalogo.programas IS 'Programas que se venden. Cada uno define sus reglas de agenda, su cupo y cuándo se evalúa al terapeuta.';
COMMENT ON COLUMN catalogo.programas.cupo_maximo IS 'Máximo de pacientes por sesión. Paramétrico: 5 en terapia grupal, 8 en inglés presencial, 30 o más en línea.';
COMMENT ON COLUMN catalogo.programas.sesiones_antes_evaluacion IS 'La familia debe evaluar al terapeuta al llegar a esta cantidad de sesiones antes del final (1 = en la penúltima).';
COMMENT ON COLUMN catalogo.programas.reglas_extra IS 'Reglas futuras en formato JSON, para no cambiar la estructura de la tabla.';
CREATE TRIGGER programas_actualizado BEFORE UPDATE ON catalogo.programas
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE INDEX programas_area ON catalogo.programas (area_id) WHERE activo;

CREATE TABLE catalogo.programa_fases (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  programa_id uuid NOT NULL REFERENCES catalogo.programas ON DELETE CASCADE,
  orden       smallint NOT NULL CHECK (orden > 0),
  nombre      text NOT NULL,
  sesiones    smallint NOT NULL CHECK (sesiones > 0),
  sub_area_id uuid REFERENCES catalogo.sub_areas,
  UNIQUE (programa_id, orden)
);
COMMENT ON TABLE catalogo.programa_fases IS 'Fases de un programa (F1, F2, F3…). Una fase puede derivar al paciente a otra especialidad.';
COMMENT ON COLUMN catalogo.programa_fases.sub_area_id IS 'Especialidad que atiende esta fase, si es distinta a la del programa (derivación).';
