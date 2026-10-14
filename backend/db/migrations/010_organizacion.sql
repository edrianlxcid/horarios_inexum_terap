-- =============================================================================
-- 010 · Organización
-- Geografía (códigos INEC), RUCs, sedes, salas y feriados.
-- =============================================================================

CREATE SCHEMA organizacion;
COMMENT ON SCHEMA organizacion IS 'Sedes, salas, feriados y geografía.';

CREATE TABLE organizacion.paises (
  id     char(2) PRIMARY KEY,
  nombre text NOT NULL,
  activo boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE organizacion.paises IS 'Países (código ISO de 2 letras).';

CREATE TABLE organizacion.provincias (
  id      integer PRIMARY KEY,
  pais_id char(2) NOT NULL REFERENCES organizacion.paises,
  nombre  text NOT NULL,
  activo  boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE organizacion.provincias IS 'Provincias (código INEC).';

CREATE TABLE organizacion.cantones (
  id           integer PRIMARY KEY,
  provincia_id integer NOT NULL REFERENCES organizacion.provincias,
  nombre       text NOT NULL,
  activo       boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE organizacion.cantones IS 'Cantones (código INEC).';

CREATE TABLE organizacion.parroquias (
  id        integer PRIMARY KEY,
  canton_id integer NOT NULL REFERENCES organizacion.cantones,
  nombre    text NOT NULL,
  activo    boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE organizacion.parroquias IS 'Parroquias (código INEC).';

CREATE TABLE organizacion.rucs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  numero_ruc  text NOT NULL UNIQUE CHECK (numero_ruc ~ '^[0-9]{13}$'),
  canton_id   integer NOT NULL REFERENCES organizacion.cantones,
  descripcion text,
  activo      boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE organizacion.rucs IS 'RUCs homologados por cantón con los que factura cada sede.';

CREATE TABLE organizacion.sedes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo         text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z0-9_]+$'),
  nombre         text NOT NULL,
  parroquia_id   integer NOT NULL REFERENCES organizacion.parroquias,
  ruc_id         uuid REFERENCES organizacion.rucs,
  direccion      text,
  telefono       text,
  zona_horaria   text NOT NULL DEFAULT 'America/Guayaquil',
  activo         boolean NOT NULL DEFAULT true,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  creado_por     uuid,
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_por uuid,
  archivado_en   timestamptz
);
COMMENT ON TABLE organizacion.sedes IS 'Sedes del centro.';
CREATE TRIGGER sedes_actualizado BEFORE UPDATE ON organizacion.sedes
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();

CREATE TABLE organizacion.salas (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sede_id   uuid NOT NULL REFERENCES organizacion.sedes,
  nombre    text NOT NULL,
  capacidad smallint NOT NULL DEFAULT 1 CHECK (capacidad > 0),
  activo    boolean NOT NULL DEFAULT true,
  UNIQUE (sede_id, nombre)
);
COMMENT ON TABLE organizacion.salas IS 'Consultorios y salas de cada sede. La capacidad limita los grupos presenciales.';

CREATE TABLE organizacion.feriados (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fecha   date NOT NULL,
  nombre  text NOT NULL,
  sede_id uuid REFERENCES organizacion.sedes,
  UNIQUE NULLS NOT DISTINCT (fecha, sede_id)
);
COMMENT ON TABLE organizacion.feriados IS 'Días sin atención. Sin sede = feriado nacional; con sede = feriado local.';
COMMENT ON COLUMN organizacion.feriados.sede_id IS 'Vacío para feriados nacionales.';
