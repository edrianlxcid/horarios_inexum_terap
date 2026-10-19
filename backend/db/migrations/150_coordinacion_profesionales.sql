-- =============================================================================
-- 150 · Coordinación registra profesionales (18/10/2026)
-- El coordinador puede dar de alta profesionales de sus áreas, con sus
-- especialidades y su horario semanal. La cuenta de acceso al sistema la
-- sigue creando Administración.
-- =============================================================================

ALTER TABLE personas.profesionales
  ADD COLUMN telefono text,
  ADD COLUMN email    text CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
COMMENT ON COLUMN personas.profesionales.email IS 'Correo de contacto. Puede ser distinto al de su cuenta de acceso.';

INSERT INTO seguridad.permisos (codigo, modulo, descripcion) VALUES
  ('personas.profesionales.registrar', 'personas', 'Registrar profesionales con sus especialidades y su horario');

INSERT INTO seguridad.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM seguridad.roles r, seguridad.permisos p
WHERE r.codigo IN ('COORDINADOR', 'ADMINISTRADOR') AND p.codigo = 'personas.profesionales.registrar';
