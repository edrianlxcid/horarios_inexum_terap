-- =============================================================================
-- 040 · Personas
-- Terapeutas, pacientes, representantes y la clasificación de demanda.
-- =============================================================================

CREATE SCHEMA personas;
COMMENT ON SCHEMA personas IS 'Terapeutas, pacientes, representantes y nivel de demanda de cada paciente.';

CREATE TABLE personas.profesionales (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid UNIQUE REFERENCES seguridad.usuarios,
  cedula          text NOT NULL UNIQUE CHECK (cedula ~ '^[0-9]{10}$'),
  nombres         text NOT NULL,
  apellidos       text NOT NULL,
  profesion       text NOT NULL,
  color_agenda    text NOT NULL DEFAULT '#1D5F8A' CHECK (color_agenda ~ '^#[0-9A-Fa-f]{6}$'),
  fecha_ingreso   date,
  activo          boolean NOT NULL DEFAULT true,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  creado_por      uuid,
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  actualizado_por uuid,
  archivado_en    timestamptz
);
COMMENT ON TABLE personas.profesionales IS 'Terapeutas y demás profesionales que atienden sesiones.';
CREATE TRIGGER profesionales_actualizado BEFORE UPDATE ON personas.profesionales
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER profesionales_auditoria AFTER INSERT OR UPDATE OR DELETE ON personas.profesionales
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();

CREATE TABLE personas.profesional_sub_areas (
  profesional_id uuid NOT NULL REFERENCES personas.profesionales ON DELETE CASCADE,
  sub_area_id    uuid NOT NULL REFERENCES catalogo.sub_areas,
  es_principal   boolean NOT NULL DEFAULT false,
  PRIMARY KEY (profesional_id, sub_area_id)
);
COMMENT ON TABLE personas.profesional_sub_areas IS 'Especialidades en las que está habilitado cada terapeuta.';
CREATE INDEX profesional_sub_areas_sub_area ON personas.profesional_sub_areas (sub_area_id);

CREATE TABLE personas.pacientes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_historia   text NOT NULL UNIQUE CHECK (codigo_historia ~ '^HC-[0-9]{5,}$'),
  cedula            bytea,
  cedula_huella     text UNIQUE,
  nombres           text NOT NULL,
  apellidos         text NOT NULL,
  fecha_nacimiento  date NOT NULL CHECK (fecha_nacimiento > date '1900-01-01'),
  sexo              text CHECK (sexo IN ('F', 'M', 'OTRO')),
  direccion         text,
  sede_principal_id uuid NOT NULL REFERENCES organizacion.sedes,
  estado            text NOT NULL DEFAULT 'PROSPECTO' CHECK (estado IN ('PROSPECTO', 'ACTIVO', 'CONGELADO', 'GRADUADO', 'RETIRADO')),
  observaciones     text,
  creado_en         timestamptz NOT NULL DEFAULT now(),
  creado_por        uuid,
  actualizado_en    timestamptz NOT NULL DEFAULT now(),
  actualizado_por   uuid,
  archivado_en      timestamptz,
  CHECK ((cedula IS NULL) = (cedula_huella IS NULL))
);
COMMENT ON TABLE personas.pacientes IS 'Pacientes (en su mayoría niños). PROSPECTO = valorado pero aún sin matrícula.';
COMMENT ON COLUMN personas.pacientes.cedula IS 'Cédula cifrada con la llave de la API.';
COMMENT ON COLUMN personas.pacientes.cedula_huella IS 'Huella de la cédula para buscar sin descifrar.';
CREATE TRIGGER pacientes_actualizado BEFORE UPDATE ON personas.pacientes
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER pacientes_auditoria AFTER INSERT OR UPDATE OR DELETE ON personas.pacientes
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar('cedula', 'cedula_huella');
CREATE INDEX pacientes_nombre_trgm ON personas.pacientes USING gin ((lower(nombres || ' ' || apellidos)) gin_trgm_ops);
CREATE INDEX pacientes_sede_estado ON personas.pacientes (sede_principal_id, estado);

CREATE TABLE personas.representantes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid UNIQUE REFERENCES seguridad.usuarios,
  cedula          text NOT NULL UNIQUE CHECK (cedula ~ '^[0-9]{10}$'),
  nombres         text NOT NULL,
  apellidos       text NOT NULL,
  telefono        text,
  email           text CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  direccion       text,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  creado_por      uuid,
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  actualizado_por uuid,
  archivado_en    timestamptz
);
COMMENT ON TABLE personas.representantes IS 'Padres, madres o tutores. Usan el portal de familias.';
CREATE TRIGGER representantes_actualizado BEFORE UPDATE ON personas.representantes
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER representantes_auditoria AFTER INSERT OR UPDATE OR DELETE ON personas.representantes
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();
CREATE INDEX representantes_nombre_trgm ON personas.representantes USING gin ((lower(nombres || ' ' || apellidos)) gin_trgm_ops);

CREATE TABLE personas.paciente_representantes (
  paciente_id           uuid NOT NULL REFERENCES personas.pacientes ON DELETE CASCADE,
  representante_id      uuid NOT NULL REFERENCES personas.representantes ON DELETE CASCADE,
  parentesco            text NOT NULL CHECK (parentesco IN ('MADRE', 'PADRE', 'ABUELA', 'ABUELO', 'TIA', 'TIO', 'TUTOR', 'OTRO')),
  es_principal          boolean NOT NULL DEFAULT false,
  recibe_notificaciones boolean NOT NULL DEFAULT true,
  PRIMARY KEY (paciente_id, representante_id)
);
COMMENT ON TABLE personas.paciente_representantes IS 'Un niño puede tener varios representantes y un representante varios hijos.';
CREATE UNIQUE INDEX paciente_un_principal ON personas.paciente_representantes (paciente_id) WHERE es_principal;
CREATE INDEX paciente_representantes_rep ON personas.paciente_representantes (representante_id);

-- -----------------------------------------------------------------------------
-- Nivel de demanda del paciente ("qué tan pesado es"): lo clasifica alguien
-- de coordinación para arriba, no el terapeuta, para que no sea subjetivo.
-- -----------------------------------------------------------------------------
CREATE TABLE personas.niveles_demanda (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo                 text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z_]+$'),
  nombre                 text NOT NULL,
  descripcion            text,
  terapeutas_requeridos  numeric(3,1) NOT NULL CHECK (terapeutas_requeridos > 0),
  peso                   smallint NOT NULL CHECK (peso > 0),
  orden                  smallint NOT NULL UNIQUE
);
COMMENT ON TABLE personas.niveles_demanda IS 'Escala de demanda del paciente. El peso sirve para medir la carga real de un grupo o un terapeuta.';

INSERT INTO personas.niveles_demanda (codigo, nombre, descripcion, terapeutas_requeridos, peso, orden) VALUES
  ('BAJA',     'Baja',     'Trabaja sin apoyo adicional.',                              1.0, 1, 1),
  ('MEDIA',    'Media',    'Necesita apoyo ocasional o adaptaciones.',                   1.0, 2, 2),
  ('ALTA',     'Alta',     'Necesita atención casi individual, aun dentro de un grupo.', 1.5, 3, 3),
  ('MUY_ALTA', 'Muy alta', 'Puede requerir dos o tres profesionales para contenerlo.',   2.5, 5, 4);

CREATE TABLE personas.clasificaciones_demanda (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id     uuid NOT NULL REFERENCES personas.pacientes ON DELETE CASCADE,
  nivel_id        uuid NOT NULL REFERENCES personas.niveles_demanda,
  motivo          text NOT NULL CHECK (length(trim(motivo)) >= 5),
  clasificado_por uuid NOT NULL REFERENCES seguridad.usuarios,
  clasificado_en  timestamptz NOT NULL DEFAULT now(),
  vigente         boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE personas.clasificaciones_demanda IS 'Historial de clasificaciones de demanda. Solo una vigente por paciente.';
CREATE UNIQUE INDEX clasificacion_vigente ON personas.clasificaciones_demanda (paciente_id) WHERE vigente;
CREATE TRIGGER clasificaciones_auditoria AFTER INSERT OR UPDATE OR DELETE ON personas.clasificaciones_demanda
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();

CREATE FUNCTION personas.tg_validar_clasificacion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_minimo smallint := (SELECT (valor #>> '{}')::smallint FROM comun.parametros WHERE clave = 'demanda.nivel_minimo_clasificador');
BEGIN
  IF seguridad.nivel_usuario(NEW.clasificado_por) < coalesce(v_minimo, 50) THEN
    RAISE EXCEPTION 'Solo coordinación, administración o gerencia pueden clasificar la demanda de un paciente.'
      USING ERRCODE = 'check_violation';
  END IF;
  -- La clasificación nueva reemplaza a la anterior.
  IF NEW.vigente THEN
    UPDATE personas.clasificaciones_demanda
       SET vigente = false
     WHERE paciente_id = NEW.paciente_id AND vigente AND id <> NEW.id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER clasificaciones_validar BEFORE INSERT ON personas.clasificaciones_demanda
  FOR EACH ROW EXECUTE FUNCTION personas.tg_validar_clasificacion();
