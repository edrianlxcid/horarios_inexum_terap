-- =============================================================================
-- 030 · Seguridad y auditoría
-- Usuarios, roles, permisos por sede y por área, sesiones y bitácora.
-- =============================================================================

CREATE SCHEMA seguridad;
COMMENT ON SCHEMA seguridad IS 'Usuarios, roles, permisos, sesiones de acceso y bitácora de auditoría.';

CREATE TABLE seguridad.usuarios (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email             text NOT NULL CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  password_hash     text NOT NULL,
  nombres           text NOT NULL,
  apellidos         text NOT NULL,
  telefono          text,
  mfa_activo        boolean NOT NULL DEFAULT false,
  mfa_secreto       bytea,
  intentos_fallidos smallint NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
  bloqueado_hasta   timestamptz,
  ultimo_acceso_en  timestamptz,
  activo            boolean NOT NULL DEFAULT true,
  creado_en         timestamptz NOT NULL DEFAULT now(),
  creado_por        uuid,
  actualizado_en    timestamptz NOT NULL DEFAULT now(),
  actualizado_por   uuid,
  archivado_en      timestamptz
);
COMMENT ON TABLE seguridad.usuarios IS 'Cuentas de acceso a las apps Equipo y Familias.';
COMMENT ON COLUMN seguridad.usuarios.password_hash IS 'Hash de la contraseña (argon2 desde la API; bcrypt en los datos de prueba). Nunca la contraseña.';
COMMENT ON COLUMN seguridad.usuarios.mfa_secreto IS 'Secreto de verificación en dos pasos, cifrado.';
CREATE UNIQUE INDEX usuarios_email ON seguridad.usuarios (lower(email));
CREATE TRIGGER usuarios_actualizado BEFORE UPDATE ON seguridad.usuarios
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();

CREATE TABLE seguridad.roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z_]+$'),
  nombre      text NOT NULL,
  descripcion text,
  nivel       smallint NOT NULL CHECK (nivel BETWEEN 0 AND 100)
);
COMMENT ON TABLE seguridad.roles IS 'Roles. Agregar uno nuevo (p. ej. Recepción) es crear una fila y asignarle permisos.';
COMMENT ON COLUMN seguridad.roles.nivel IS 'Jerarquía: 90 Gerencia, 80 Administrador, 50 Coordinador, 30 Terapeuta, 10 Representante.';

INSERT INTO seguridad.roles (codigo, nombre, descripcion, nivel) VALUES
  ('GERENCIA',      'Gerencia',      'Indicadores y reportes de todas las sedes y áreas.',             90),
  ('ADMINISTRADOR', 'Administrador', 'Configura usuarios, sedes, programas, jornadas y feriados.',      80),
  ('COORDINADOR',   'Coordinador',   'Pacientes, matrículas y agenda de sus sedes y su área.',         50),
  ('TERAPEUTA',     'Terapeuta',     'Su agenda, sus pacientes, asistencia y notas de sesión.',        30),
  ('REPRESENTANTE', 'Representante', 'Portal de familias: sesiones, progreso y evaluación del terapeuta.', 10);

CREATE TABLE seguridad.permisos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      text NOT NULL UNIQUE CHECK (codigo ~ '^[a-z_]+(\.[a-z_]+)+$'),
  modulo      text NOT NULL,
  descripcion text NOT NULL
);
COMMENT ON TABLE seguridad.permisos IS 'Acciones que se pueden permitir a un rol, con formato modulo.recurso.accion.';

CREATE TABLE seguridad.rol_permisos (
  rol_id     uuid NOT NULL REFERENCES seguridad.roles ON DELETE CASCADE,
  permiso_id uuid NOT NULL REFERENCES seguridad.permisos ON DELETE CASCADE,
  PRIMARY KEY (rol_id, permiso_id)
);
COMMENT ON TABLE seguridad.rol_permisos IS 'Qué permisos tiene cada rol.';

CREATE TABLE seguridad.usuario_roles (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    uuid NOT NULL REFERENCES seguridad.usuarios ON DELETE CASCADE,
  rol_id        uuid NOT NULL REFERENCES seguridad.roles,
  sede_id       uuid REFERENCES organizacion.sedes,
  area_id       uuid REFERENCES catalogo.areas,
  vigente_desde date NOT NULL DEFAULT current_date,
  vigente_hasta date,
  CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde),
  UNIQUE NULLS NOT DISTINCT (usuario_id, rol_id, sede_id, area_id)
);
COMMENT ON TABLE seguridad.usuario_roles IS 'Roles de cada usuario, limitados por sede y por área. Un coordinador puede tener varias filas (p. ej. Norte y Tumbaco).';
COMMENT ON COLUMN seguridad.usuario_roles.sede_id IS 'Vacío = todas las sedes.';
COMMENT ON COLUMN seguridad.usuario_roles.area_id IS 'Vacío = todas las áreas. Un coordinador de Neuro no ve informes de Inglés/Estimulación.';
CREATE INDEX usuario_roles_usuario ON seguridad.usuario_roles (usuario_id);

CREATE TABLE seguridad.sesiones_usuario (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id         uuid NOT NULL REFERENCES seguridad.usuarios ON DELETE CASCADE,
  refresh_token_hash text NOT NULL UNIQUE,
  app                text NOT NULL CHECK (app IN ('EQUIPO', 'FAMILIAS')),
  dispositivo        text,
  ip                 inet,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  expira_en          timestamptz NOT NULL,
  revocado_en        timestamptz,
  CHECK (expira_en > creado_en)
);
COMMENT ON TABLE seguridad.sesiones_usuario IS 'Sesiones abiertas. Solo se guarda el hash del token de renovación.';
CREATE INDEX sesiones_usuario_activas ON seguridad.sesiones_usuario (usuario_id) WHERE revocado_en IS NULL;

-- Nivel más alto que tiene un usuario hoy (para reglas como "de coordinación para arriba").
CREATE FUNCTION seguridad.nivel_usuario(p_usuario uuid) RETURNS smallint
LANGUAGE sql STABLE AS $$
  SELECT coalesce(max(r.nivel), 0)::smallint
  FROM seguridad.usuario_roles ur
  JOIN seguridad.roles r ON r.id = ur.rol_id
  JOIN seguridad.usuarios u ON u.id = ur.usuario_id
  WHERE ur.usuario_id = p_usuario
    AND u.activo AND u.archivado_en IS NULL
    AND current_date BETWEEN ur.vigente_desde AND coalesce(ur.vigente_hasta, 'infinity'::date)
$$;

-- -----------------------------------------------------------------------------
-- Bitácora de auditoría, dividida por mes para que siga rápida con los años.
-- -----------------------------------------------------------------------------
CREATE TABLE seguridad.bitacora (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  ocurrido_en timestamptz NOT NULL DEFAULT now(),
  usuario_id  uuid,
  accion      text NOT NULL CHECK (accion IN ('CREAR', 'EDITAR', 'ELIMINAR', 'VER', 'LOGIN', 'LOGIN_FALLIDO', 'LOGOUT')),
  esquema     text,
  tabla       text,
  registro_id text,
  antes       jsonb,
  despues     jsonb,
  ip          inet,
  PRIMARY KEY (id, ocurrido_en)
) PARTITION BY RANGE (ocurrido_en);
COMMENT ON TABLE seguridad.bitacora IS 'Quién hizo qué y cuándo. Incluye las lecturas de historiales clínicos (acción VER).';

CREATE TABLE seguridad.bitacora_historica PARTITION OF seguridad.bitacora DEFAULT;
DO $$
DECLARE
  mes date := date '2026-01-01';
BEGIN
  WHILE mes < date '2028-01-01' LOOP
    EXECUTE format(
      'CREATE TABLE seguridad.%I PARTITION OF seguridad.bitacora FOR VALUES FROM (%L) TO (%L)',
      'bitacora_' || to_char(mes, 'YYYY_MM'), mes, (mes + interval '1 month')::date);
    mes := (mes + interval '1 month')::date;
  END LOOP;
END $$;
CREATE INDEX bitacora_registro ON seguridad.bitacora (tabla, registro_id);
CREATE INDEX bitacora_usuario ON seguridad.bitacora (usuario_id, ocurrido_en);

-- Registra cambios. Los argumentos del trigger son columnas que NO se copian
-- a la bitácora (datos cifrados o pesados).
CREATE FUNCTION seguridad.tg_auditar() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_antes   jsonb;
  v_despues jsonb;
  v_col     text;
BEGIN
  IF current_setting('app.omitir_auditoria', true) = 'on' THEN
    RETURN NULL;
  END IF;
  IF TG_OP <> 'INSERT' THEN v_antes := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN v_despues := to_jsonb(NEW); END IF;
  FOREACH v_col IN ARRAY TG_ARGV LOOP
    v_antes := v_antes - v_col;
    v_despues := v_despues - v_col;
  END LOOP;
  INSERT INTO seguridad.bitacora (usuario_id, accion, esquema, tabla, registro_id, antes, despues)
  VALUES (
    comun.usuario_actual(),
    CASE TG_OP WHEN 'INSERT' THEN 'CREAR' WHEN 'UPDATE' THEN 'EDITAR' ELSE 'ELIMINAR' END,
    TG_TABLE_SCHEMA, TG_TABLE_NAME,
    coalesce(v_despues, v_antes) ->> 'id',
    v_antes, v_despues);
  RETURN NULL;
END $$;

-- La API llama a esta función cada vez que alguien abre un historial clínico.
CREATE FUNCTION seguridad.registrar_lectura(p_tabla text, p_registro_id text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO seguridad.bitacora (usuario_id, accion, esquema, tabla, registro_id)
  VALUES (comun.usuario_actual(), 'VER', split_part(p_tabla, '.', 1), split_part(p_tabla, '.', 2), p_registro_id)
$$;

CREATE TRIGGER usuarios_auditoria AFTER INSERT OR UPDATE OR DELETE ON seguridad.usuarios
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar('password_hash', 'mfa_secreto');
CREATE TRIGGER usuario_roles_auditoria AFTER INSERT OR UPDATE OR DELETE ON seguridad.usuario_roles
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();
