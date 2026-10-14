-- =============================================================================
-- 000 · Núcleo compartido
-- Extensiones, parámetros generales y funciones que usan todos los módulos.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- gen_random_uuid(), cifrado y hash
CREATE EXTENSION IF NOT EXISTS btree_gist;  -- restricciones de exclusión (choques de horario)
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- búsqueda aproximada por nombre

CREATE SCHEMA comun;
COMMENT ON SCHEMA comun IS 'Núcleo compartido: parámetros y funciones usadas por todos los módulos.';

-- Parámetros del negocio que se pueden cambiar sin programar.
CREATE TABLE comun.parametros (
  clave          text PRIMARY KEY CHECK (clave ~ '^[a-z_.]+$'),
  valor          jsonb NOT NULL,
  descripcion    text NOT NULL,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE comun.parametros IS 'Parámetros del negocio editables sin programar (cupos por defecto, zona horaria, etc.).';

INSERT INTO comun.parametros (clave, valor, descripcion) VALUES
  ('agenda.zona_horaria',              '"America/Guayaquil"', 'Zona horaria por defecto de las sedes.'),
  ('agenda.duracion_sesion_min',       '60',                  'Duración por defecto de una sesión, en minutos.'),
  ('grupos.cupo_por_defecto',          '5',                   'Cupo sugerido al crear un programa grupal. Cada programa puede definir el suyo.'),
  ('evaluacion.sesiones_antes_del_fin','1',                   'Cuántas sesiones antes del final se exige a la familia evaluar al terapeuta.'),
  ('demanda.nivel_minimo_clasificador','50',                  'Nivel de rol mínimo para clasificar la demanda de un paciente (50 = coordinación).');

-- Mantiene actualizado_en al día en cada UPDATE.
CREATE FUNCTION comun.tg_actualizado_en() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en := now();
  RETURN NEW;
END $$;

-- Usuario de la aplicación que hace el cambio. La API lo fija con
-- SET LOCAL app.usuario_id = '<uuid>' al inicio de cada transacción.
CREATE FUNCTION comun.usuario_actual() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.usuario_id', true), '')::uuid
$$;

-- Cifrado simétrico de datos sensibles. La llave nunca se guarda en la base:
-- la API la envía en cada consulta desde sus variables de entorno.
CREATE FUNCTION comun.cifrar(p_texto text, p_llave text) RETURNS bytea
LANGUAGE sql VOLATILE AS $$
  SELECT CASE WHEN p_texto IS NULL THEN NULL ELSE pgp_sym_encrypt(p_texto, p_llave, 'cipher-algo=aes256') END
$$;

CREATE FUNCTION comun.descifrar(p_dato bytea, p_llave text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_dato IS NULL THEN NULL ELSE pgp_sym_decrypt(p_dato, p_llave) END
$$;

-- Huella para buscar un dato cifrado (por ejemplo una cédula) sin descifrarlo.
CREATE FUNCTION comun.huella(p_texto text, p_llave text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_texto IS NULL THEN NULL ELSE encode(hmac(p_texto, p_llave, 'sha256'), 'hex') END
$$;
