-- =============================================================================
-- 090 · Notificaciones
-- Versión 1: notificación en el celular (push), correo y avisos dentro de la app.
-- El canal WhatsApp queda previsto, pero está pendiente.
-- =============================================================================

CREATE SCHEMA notificaciones;
COMMENT ON SCHEMA notificaciones IS 'Dispositivos, notificaciones enviadas y preferencias de cada usuario.';

CREATE TABLE notificaciones.dispositivos (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id uuid NOT NULL REFERENCES seguridad.usuarios ON DELETE CASCADE,
  plataforma text NOT NULL CHECK (plataforma IN ('ANDROID', 'IOS', 'WEB')),
  token_push text NOT NULL UNIQUE,
  ultimo_uso timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notificaciones.dispositivos IS 'Celulares y navegadores registrados para recibir notificaciones push.';
CREATE INDEX dispositivos_usuario ON notificaciones.dispositivos (usuario_id);

CREATE TABLE notificaciones.notificaciones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES seguridad.usuarios ON DELETE CASCADE,
  canal           text NOT NULL CHECK (canal IN ('PUSH', 'CORREO', 'APP', 'WHATSAPP')),
  tipo            text NOT NULL CHECK (tipo IN ('RECORDATORIO_SESION', 'CAMBIO_AGENDA', 'TAREA_NUEVA', 'EVALUACION_PENDIENTE', 'GENERAL')),
  titulo          text NOT NULL,
  cuerpo          text NOT NULL,
  datos           jsonb NOT NULL DEFAULT '{}'::jsonb,
  programada_para timestamptz NOT NULL DEFAULT now(),
  enviada_en      timestamptz,
  leida_en        timestamptz,
  error           text
);
COMMENT ON TABLE notificaciones.notificaciones IS 'Bandeja de notificaciones. WHATSAPP queda reservado hasta que se habilite.';
CREATE INDEX notificaciones_no_leidas ON notificaciones.notificaciones (usuario_id, programada_para) WHERE leida_en IS NULL;
CREATE INDEX notificaciones_por_enviar ON notificaciones.notificaciones (programada_para) WHERE enviada_en IS NULL;

CREATE TABLE notificaciones.preferencias (
  usuario_id uuid NOT NULL REFERENCES seguridad.usuarios ON DELETE CASCADE,
  tipo       text NOT NULL,
  canal      text NOT NULL CHECK (canal IN ('PUSH', 'CORREO', 'APP', 'WHATSAPP')),
  activo     boolean NOT NULL DEFAULT true,
  PRIMARY KEY (usuario_id, tipo, canal)
);
COMMENT ON TABLE notificaciones.preferencias IS 'Qué avisos quiere recibir cada usuario y por qué canal.';
