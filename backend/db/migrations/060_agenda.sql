-- =============================================================================
-- 060 · Agenda (núcleo del sistema)
-- Jornadas, pausas, ausencias, grupos, planes, sesiones y participantes.
-- Una sesión = un terapeuta en un horario, con 1 o más participantes según el cupo.
-- =============================================================================

CREATE SCHEMA agenda;
COMMENT ON SCHEMA agenda IS 'Jornadas, pausas, ausencias, grupos, sesiones, participantes y solicitudes de cambio.';

-- -----------------------------------------------------------------------------
-- Disponibilidad de los terapeutas
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.jornadas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profesional_id uuid NOT NULL REFERENCES personas.profesionales ON DELETE CASCADE,
  sede_id        uuid NOT NULL REFERENCES organizacion.sedes,
  dia_semana     smallint NOT NULL CHECK (dia_semana BETWEEN 1 AND 6),
  hora_inicio    time NOT NULL,
  hora_fin       time NOT NULL,
  vigente_desde  date NOT NULL DEFAULT current_date,
  vigente_hasta  date,
  minutos        int4range GENERATED ALWAYS AS (
                   int4range((extract(epoch FROM hora_inicio) / 60)::int, (extract(epoch FROM hora_fin) / 60)::int)) STORED,
  vigencia       daterange GENERATED ALWAYS AS (daterange(vigente_desde, vigente_hasta, '[]')) STORED,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  CHECK (hora_fin > hora_inicio),
  CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde),
  CONSTRAINT jornadas_sin_superposicion EXCLUDE USING gist (
    profesional_id WITH =, dia_semana WITH =, minutos WITH &&, vigencia WITH &&)
);
COMMENT ON TABLE agenda.jornadas IS 'Horario de trabajo de cada terapeuta por día y sede, de lunes (1) a sábado (6). Los domingos no se atiende.';
COMMENT ON COLUMN agenda.jornadas.vigente_hasta IS 'Vacío = sigue vigente. Cambiar un horario cierra la jornada vieja sin perder el historial.';
CREATE TRIGGER jornadas_actualizado BEFORE UPDATE ON agenda.jornadas
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();

CREATE TABLE agenda.pausas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profesional_id uuid NOT NULL REFERENCES personas.profesionales ON DELETE CASCADE,
  dia_semana     smallint NOT NULL CHECK (dia_semana BETWEEN 1 AND 6),
  hora_inicio    time NOT NULL,
  hora_fin       time NOT NULL,
  tipo           text NOT NULL CHECK (tipo IN ('ALMUERZO', 'ADMINISTRATIVA')),
  vigente_desde  date NOT NULL DEFAULT current_date,
  vigente_hasta  date,
  CHECK (hora_fin > hora_inicio)
);
COMMENT ON TABLE agenda.pausas IS 'Almuerzo y horas administrativas recurrentes de cada terapeuta (antes estaban fijas a las 13:00 en el código).';
CREATE INDEX pausas_profesional ON agenda.pausas (profesional_id, dia_semana);

CREATE TABLE agenda.ausencias (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profesional_id uuid NOT NULL REFERENCES personas.profesionales ON DELETE CASCADE,
  inicio         timestamptz NOT NULL,
  fin            timestamptz NOT NULL,
  tipo           text NOT NULL CHECK (tipo IN ('VACACIONES', 'PERMISO', 'ENFERMEDAD', 'CAPACITACION')),
  motivo         text,
  aprobado_por   uuid REFERENCES seguridad.usuarios,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  CHECK (fin > inicio)
);
COMMENT ON TABLE agenda.ausencias IS 'Vacaciones, permisos y otras ausencias puntuales. El motor no agenda en esos rangos.';
CREATE INDEX ausencias_profesional ON agenda.ausencias USING gist (profesional_id, tstzrange(inicio, fin));

-- -----------------------------------------------------------------------------
-- Grupos: el terapeuta o el coordinador decide quién va en cada grupo
-- (sin regla fija de edad, por decisión de la reunión del 5/10/2026).
-- El sistema solo controla el cupo.
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.grupos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo          text NOT NULL UNIQUE CHECK (codigo ~ '^G-[0-9]{2,5}$'),
  programa_id     uuid NOT NULL REFERENCES catalogo.programas,
  sede_id         uuid NOT NULL REFERENCES organizacion.sedes,
  profesional_id  uuid NOT NULL REFERENCES personas.profesionales,
  sala_id         uuid REFERENCES organizacion.salas,
  cupo_maximo     smallint NOT NULL CHECK (cupo_maximo >= 2),
  activo          boolean NOT NULL DEFAULT true,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  creado_por      uuid,
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  actualizado_por uuid
);
COMMENT ON TABLE agenda.grupos IS 'Grupos estables (G-64). Quién entra lo decide el terapeuta o el coordinador; el sistema controla el cupo.';
CREATE TRIGGER grupos_actualizado BEFORE UPDATE ON agenda.grupos
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER grupos_auditoria AFTER INSERT OR UPDATE OR DELETE ON agenda.grupos
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();

CREATE FUNCTION agenda.tg_validar_grupo() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_prog catalogo.programas%ROWTYPE;
BEGIN
  SELECT * INTO v_prog FROM catalogo.programas WHERE id = NEW.programa_id;
  IF v_prog.modalidad = 'INDIVIDUAL' THEN
    RAISE EXCEPTION 'El programa "%" es individual: no admite grupos.', v_prog.nombre
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.cupo_maximo > v_prog.cupo_maximo THEN
    RAISE EXCEPTION 'El cupo del grupo (%) supera el máximo del programa "%" (%).', NEW.cupo_maximo, v_prog.nombre, v_prog.cupo_maximo
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER grupos_validar BEFORE INSERT OR UPDATE OF programa_id, cupo_maximo ON agenda.grupos
  FOR EACH ROW EXECUTE FUNCTION agenda.tg_validar_grupo();

CREATE TABLE agenda.grupo_miembros (
  grupo_id     uuid NOT NULL REFERENCES agenda.grupos ON DELETE CASCADE,
  matricula_id uuid NOT NULL REFERENCES matriculas.matriculas,
  desde        date NOT NULL,
  hasta        date,
  PRIMARY KEY (grupo_id, matricula_id),
  CHECK (hasta IS NULL OR hasta >= desde)
);
COMMENT ON TABLE agenda.grupo_miembros IS 'Matrículas que forman parte de cada grupo y desde cuándo.';
CREATE INDEX grupo_miembros_matricula ON agenda.grupo_miembros (matricula_id);

CREATE FUNCTION agenda.tg_validar_miembro() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_grupo    agenda.grupos%ROWTYPE;
  v_miembros int;
BEGIN
  SELECT * INTO v_grupo FROM agenda.grupos WHERE id = NEW.grupo_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM matriculas.matriculas m WHERE m.id = NEW.matricula_id AND m.programa_id = v_grupo.programa_id) THEN
    RAISE EXCEPTION 'La matrícula no es del mismo programa que el grupo %.', v_grupo.codigo
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT count(*) INTO v_miembros
  FROM agenda.grupo_miembros g
  WHERE g.grupo_id = NEW.grupo_id AND g.matricula_id <> NEW.matricula_id
    AND daterange(g.desde, g.hasta, '[]') && daterange(NEW.desde, NEW.hasta, '[]');
  IF v_miembros >= v_grupo.cupo_maximo THEN
    RAISE EXCEPTION 'El grupo % ya tiene su cupo completo (% de %).', v_grupo.codigo, v_miembros, v_grupo.cupo_maximo
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER grupo_miembros_validar BEFORE INSERT OR UPDATE ON agenda.grupo_miembros
  FOR EACH ROW EXECUTE FUNCTION agenda.tg_validar_miembro();

-- -----------------------------------------------------------------------------
-- Planes de agenda: el patrón con el que el motor genera las sesiones.
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.planes_agenda (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matricula_id       uuid NOT NULL REFERENCES matriculas.matriculas,
  grupo_id           uuid REFERENCES agenda.grupos,
  fecha_inicio       date NOT NULL,
  patron             jsonb NOT NULL CHECK (jsonb_typeof(patron) = 'array'),
  sesiones_a_generar smallint NOT NULL CHECK (sesiones_a_generar > 0),
  estado             text NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'PAUSADO', 'FINALIZADO')),
  creado_en          timestamptz NOT NULL DEFAULT now(),
  creado_por         uuid
);
COMMENT ON TABLE agenda.planes_agenda IS 'Patrón semanal (días, horas y terapeuta) con el que se generaron las sesiones de una matrícula.';
COMMENT ON COLUMN agenda.planes_agenda.patron IS 'Ejemplo: [{"dia":2,"hora":"15:00","profesional_id":"…"},{"dia":4,"hora":"15:00","profesional_id":"…"}]';
CREATE INDEX planes_matricula ON agenda.planes_agenda (matricula_id);

-- -----------------------------------------------------------------------------
-- Sesiones
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.sesiones (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sede_id            uuid NOT NULL REFERENCES organizacion.sedes,
  sala_id            uuid REFERENCES organizacion.salas,
  profesional_id     uuid NOT NULL REFERENCES personas.profesionales,
  programa_id        uuid REFERENCES catalogo.programas,
  grupo_id           uuid REFERENCES agenda.grupos,
  plan_id            uuid REFERENCES agenda.planes_agenda,
  tipo               text NOT NULL CHECK (tipo IN ('VALORACION', 'PROGRAMA', 'REPOSICION', 'REUNION')),
  modalidad_entrega  text NOT NULL DEFAULT 'PRESENCIAL' CHECK (modalidad_entrega IN ('PRESENCIAL', 'ONLINE')),
  inicio             timestamptz NOT NULL,
  fin                timestamptz NOT NULL,
  rango              tstzrange GENERATED ALWAYS AS (tstzrange(inicio, fin, '[)')) STORED,
  cupo_maximo        smallint NOT NULL DEFAULT 1 CHECK (cupo_maximo >= 1),
  estado             text NOT NULL DEFAULT 'PROGRAMADA' CHECK (estado IN ('PROGRAMADA', 'REALIZADA', 'CANCELADA')),
  motivo_cancelacion text,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  creado_por         uuid,
  actualizado_en     timestamptz NOT NULL DEFAULT now(),
  actualizado_por    uuid,
  CHECK (fin > inicio),
  CONSTRAINT sesiones_valoracion_individual CHECK (tipo <> 'VALORACION' OR cupo_maximo = 1),
  CONSTRAINT sesiones_programa_requerido CHECK (tipo NOT IN ('PROGRAMA', 'REPOSICION') OR programa_id IS NOT NULL),
  CONSTRAINT sesiones_cancelacion_con_motivo CHECK (estado <> 'CANCELADA' OR motivo_cancelacion IS NOT NULL),
  -- Regla 1: un terapeuta no puede tener dos sesiones superpuestas.
  CONSTRAINT sesiones_sin_choque EXCLUDE USING gist (profesional_id WITH =, rango WITH &&) WHERE (estado <> 'CANCELADA')
);
COMMENT ON TABLE agenda.sesiones IS 'Un terapeuta en un horario. Puede tener de 1 participante (individual) hasta el cupo del programa (grupal).';
CREATE TRIGGER sesiones_actualizado BEFORE UPDATE ON agenda.sesiones
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER sesiones_auditoria AFTER INSERT OR UPDATE OR DELETE ON agenda.sesiones
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar('rango');
CREATE INDEX sesiones_sede_inicio ON agenda.sesiones (sede_id, inicio);
CREATE INDEX sesiones_profesional_inicio ON agenda.sesiones (profesional_id, inicio);
CREATE INDEX sesiones_grupo ON agenda.sesiones (grupo_id) WHERE grupo_id IS NOT NULL;
CREATE INDEX sesiones_plan ON agenda.sesiones (plan_id) WHERE plan_id IS NOT NULL;

-- Motor de agendamiento, lado base de datos: valida cada sesión.
CREATE FUNCTION agenda.tg_validar_sesion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_zona   text;
  v_ini    timestamp;
  v_fin    timestamp;
  v_dia    smallint;
  v_prog   catalogo.programas%ROWTYPE;
  v_grupo  agenda.grupos%ROWTYPE;
  v_feriado text;
BEGIN
  IF NEW.estado = 'CANCELADA' THEN
    RETURN NEW;
  END IF;
  -- Marcar como realizada una sesión que ya era válida no vuelve a validar el horario.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.estado <> 'CANCELADA'
       AND NEW.inicio = OLD.inicio AND NEW.fin = OLD.fin
       AND NEW.profesional_id = OLD.profesional_id AND NEW.sede_id = OLD.sede_id
       AND NEW.programa_id IS NOT DISTINCT FROM OLD.programa_id
       AND NEW.grupo_id IS NOT DISTINCT FROM OLD.grupo_id
       AND NEW.cupo_maximo = OLD.cupo_maximo AND NEW.tipo = OLD.tipo THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT zona_horaria INTO v_zona FROM organizacion.sedes WHERE id = NEW.sede_id;
  v_ini := NEW.inicio AT TIME ZONE v_zona;
  v_fin := NEW.fin AT TIME ZONE v_zona;
  v_dia := extract(isodow FROM v_ini);

  IF v_ini::date <> v_fin::date THEN
    RAISE EXCEPTION 'Una sesión debe empezar y terminar el mismo día.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_dia = 7 THEN
    RAISE EXCEPTION 'No se agendan sesiones los domingos.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT f.nombre INTO v_feriado FROM organizacion.feriados f
  WHERE f.fecha = v_ini::date AND (f.sede_id IS NULL OR f.sede_id = NEW.sede_id)
  LIMIT 1;
  IF v_feriado IS NOT NULL THEN
    RAISE EXCEPTION 'El % es feriado (%): no se agendan sesiones.', to_char(v_ini, 'DD/MM/YYYY'), v_feriado
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.tipo <> 'REUNION' THEN
    IF NOT EXISTS (
      SELECT 1 FROM agenda.jornadas j
      WHERE j.profesional_id = NEW.profesional_id AND j.sede_id = NEW.sede_id
        AND j.dia_semana = v_dia AND j.vigencia @> v_ini::date
        AND v_ini::time >= j.hora_inicio AND v_fin::time <= j.hora_fin
    ) THEN
      RAISE EXCEPTION 'El horario (% a %) está fuera de la jornada del terapeuta en esta sede.',
        to_char(v_ini, 'TMDy DD/MM HH24:MI'), to_char(v_fin, 'HH24:MI')
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (
      SELECT 1 FROM agenda.pausas p
      WHERE p.profesional_id = NEW.profesional_id AND p.dia_semana = v_dia
        AND daterange(p.vigente_desde, p.vigente_hasta, '[]') @> v_ini::date
        AND v_ini::time < p.hora_fin AND v_fin::time > p.hora_inicio
    ) THEN
      RAISE EXCEPTION 'El horario choca con el almuerzo o las horas administrativas del terapeuta.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM agenda.ausencias a
    WHERE a.profesional_id = NEW.profesional_id AND tstzrange(a.inicio, a.fin) && tstzrange(NEW.inicio, NEW.fin)
  ) THEN
    RAISE EXCEPTION 'El terapeuta está ausente (vacaciones, permiso o capacitación) en ese horario.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.programa_id IS NOT NULL THEN
    SELECT * INTO v_prog FROM catalogo.programas WHERE id = NEW.programa_id;
    IF NEW.cupo_maximo > v_prog.cupo_maximo THEN
      RAISE EXCEPTION 'El cupo de la sesión (%) supera el del programa "%" (%).', NEW.cupo_maximo, v_prog.nombre, v_prog.cupo_maximo
        USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM personas.profesional_sub_areas psa
      WHERE psa.profesional_id = NEW.profesional_id
        AND (psa.sub_area_id = v_prog.sub_area_requerida_id
             OR psa.sub_area_id IN (SELECT f.sub_area_id FROM catalogo.programa_fases f
                                    WHERE f.programa_id = v_prog.id AND f.sub_area_id IS NOT NULL))
    ) THEN
      RAISE EXCEPTION 'El terapeuta no está habilitado en la especialidad del programa "%".', v_prog.nombre
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.grupo_id IS NOT NULL THEN
    SELECT * INTO v_grupo FROM agenda.grupos WHERE id = NEW.grupo_id;
    IF NEW.programa_id IS DISTINCT FROM v_grupo.programa_id THEN
      RAISE EXCEPTION 'La sesión y el grupo % deben ser del mismo programa.', v_grupo.codigo
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.cupo_maximo > v_grupo.cupo_maximo THEN
      RAISE EXCEPTION 'El cupo de la sesión supera el del grupo %.', v_grupo.codigo
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END $$;
CREATE TRIGGER sesiones_validar BEFORE INSERT OR UPDATE ON agenda.sesiones
  FOR EACH ROW EXECUTE FUNCTION agenda.tg_validar_sesion();

-- -----------------------------------------------------------------------------
-- Participantes de cada sesión
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.participantes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id       uuid NOT NULL REFERENCES agenda.sesiones ON DELETE CASCADE,
  paciente_id     uuid NOT NULL REFERENCES personas.pacientes,
  matricula_id    uuid REFERENCES matriculas.matriculas,
  numero_sesion   smallint CHECK (numero_sesion > 0),
  fase_id         uuid REFERENCES catalogo.programa_fases,
  asistencia      text NOT NULL DEFAULT 'PENDIENTE'
                  CHECK (asistencia IN ('PENDIENTE', 'ASISTIO', 'FALTA', 'FALTA_JUSTIFICADA', 'CANCELADA', 'REPROGRAMADA')),
  marcado_por     uuid REFERENCES seguridad.usuarios,
  marcado_en      timestamptz,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  creado_por      uuid,
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  actualizado_por uuid,
  UNIQUE (sesion_id, paciente_id)
);
COMMENT ON TABLE agenda.participantes IS 'Pacientes en cada sesión y su asistencia. Consume una sesión de la matrícula salvo falta justificada, cancelación o reprogramación.';
COMMENT ON COLUMN agenda.participantes.numero_sesion IS 'Número de sesión dentro de la matrícula (ej. 14 de 32).';
CREATE TRIGGER participantes_actualizado BEFORE UPDATE ON agenda.participantes
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();
CREATE TRIGGER participantes_auditoria AFTER INSERT OR UPDATE OR DELETE ON agenda.participantes
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();
CREATE INDEX participantes_paciente ON agenda.participantes (paciente_id);
CREATE INDEX participantes_matricula ON agenda.participantes (matricula_id) WHERE matricula_id IS NOT NULL;

CREATE FUNCTION agenda.tg_validar_participante() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  s                    agenda.sesiones%ROWTYPE;
  m                    record;
  v_reubica            boolean := true;
  v_cambia_matricula   boolean := true;
  v_recupera_consumo   boolean := false;
  v_ocupados           int;
  v_consumidas         int;
  v_zona               text;
BEGIN
  IF NEW.asistencia IN ('CANCELADA', 'REPROGRAMADA') THEN
    RETURN NEW;
  END IF;

  SELECT * INTO s FROM agenda.sesiones WHERE id = NEW.sesion_id FOR UPDATE;
  IF TG_OP = 'UPDATE' THEN
    v_reubica := NEW.sesion_id <> OLD.sesion_id
              OR NEW.paciente_id <> OLD.paciente_id
              OR OLD.asistencia IN ('CANCELADA', 'REPROGRAMADA');
    v_cambia_matricula := NEW.matricula_id IS DISTINCT FROM OLD.matricula_id;
    v_recupera_consumo := OLD.asistencia = 'FALTA_JUSTIFICADA';
  END IF;

  IF v_reubica THEN
    IF s.estado = 'CANCELADA' THEN
      RAISE EXCEPTION 'No se pueden agregar pacientes a una sesión cancelada.' USING ERRCODE = 'check_violation';
    END IF;

    -- Regla 3: cupo de la sesión.
    SELECT count(*) INTO v_ocupados FROM agenda.participantes p
    WHERE p.sesion_id = NEW.sesion_id AND p.id <> NEW.id
      AND p.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA');
    IF v_ocupados >= s.cupo_maximo THEN
      RAISE EXCEPTION 'La sesión ya tiene su cupo completo (% de %).', v_ocupados, s.cupo_maximo
        USING ERRCODE = 'check_violation';
    END IF;

    -- Regla 2: el paciente no puede estar en dos sesiones a la vez, en ningún programa.
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.paciente_id::text, 0));
    IF EXISTS (
      SELECT 1 FROM agenda.participantes p
      JOIN agenda.sesiones o ON o.id = p.sesion_id
      WHERE p.paciente_id = NEW.paciente_id AND p.id <> NEW.id
        AND p.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')
        AND o.estado <> 'CANCELADA' AND o.rango && s.rango
    ) THEN
      RAISE EXCEPTION 'El paciente ya tiene otra sesión a esa hora (en este u otro programa).'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF s.tipo IN ('PROGRAMA', 'REPOSICION') THEN
    IF NEW.matricula_id IS NULL THEN
      RAISE EXCEPTION 'Las sesiones de programa requieren la matrícula del paciente.' USING ERRCODE = 'check_violation';
    END IF;
    SELECT mt.*, c.estado AS estado_contrato INTO m
    FROM matriculas.matriculas mt JOIN matriculas.contratos c ON c.id = mt.contrato_id
    WHERE mt.id = NEW.matricula_id;
    IF m.paciente_id <> NEW.paciente_id OR m.programa_id <> s.programa_id THEN
      RAISE EXCEPTION 'La matrícula no corresponde a este paciente o a este programa.' USING ERRCODE = 'check_violation';
    END IF;

    IF v_reubica OR v_cambia_matricula THEN
      -- Regla 8: solo con matrícula en curso y contrato vigente.
      IF m.estado <> 'EN_CURSO' OR m.estado_contrato <> 'VIGENTE' THEN
        RAISE EXCEPTION 'La matrícula no está en curso o el contrato no está vigente.' USING ERRCODE = 'check_violation';
      END IF;
      SELECT zona_horaria INTO v_zona FROM organizacion.sedes WHERE id = s.sede_id;
      IF EXISTS (
        SELECT 1 FROM matriculas.congelamientos k
        WHERE k.matricula_id = m.id AND (s.inicio AT TIME ZONE v_zona)::date BETWEEN k.desde AND k.hasta
      ) THEN
        RAISE EXCEPTION 'La matrícula está congelada en esa fecha.' USING ERRCODE = 'check_violation';
      END IF;
    END IF;

    -- Saldo de sesiones (una falta justificada no consume).
    IF NEW.asistencia <> 'FALTA_JUSTIFICADA'
       AND (v_reubica OR v_recupera_consumo OR v_cambia_matricula) THEN
      SELECT count(*) INTO v_consumidas FROM agenda.participantes p
      WHERE p.matricula_id = m.id AND p.id <> NEW.id
        AND p.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA');
      IF v_consumidas >= m.sesiones_contratadas THEN
        RAISE EXCEPTION 'La matrícula ya no tiene sesiones disponibles (% de %).', v_consumidas, m.sesiones_contratadas
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END $$;
CREATE TRIGGER participantes_validar BEFORE INSERT OR UPDATE ON agenda.participantes
  FOR EACH ROW EXECUTE FUNCTION agenda.tg_validar_participante();

-- -----------------------------------------------------------------------------
-- Solicitudes de cambio (reprogramar o cancelar)
-- -----------------------------------------------------------------------------
CREATE TABLE agenda.solicitudes_cambio (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  participante_id  uuid NOT NULL REFERENCES agenda.participantes ON DELETE CASCADE,
  solicitado_por   uuid NOT NULL REFERENCES seguridad.usuarios,
  origen           text NOT NULL CHECK (origen IN ('FAMILIA', 'CENTRO')),
  tipo             text NOT NULL CHECK (tipo IN ('REPROGRAMAR', 'CANCELAR')),
  motivo           text NOT NULL,
  propuesta_inicio timestamptz,
  estado           text NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE', 'APROBADA', 'RECHAZADA')),
  resuelto_por     uuid REFERENCES seguridad.usuarios,
  resuelto_en      timestamptz,
  creado_en        timestamptz NOT NULL DEFAULT now(),
  CHECK ((estado = 'PENDIENTE') = (resuelto_en IS NULL))
);
COMMENT ON TABLE agenda.solicitudes_cambio IS 'Pedidos de reprogramación o cancelación. El coordinador los aprueba o rechaza.';
CREATE INDEX solicitudes_pendientes ON agenda.solicitudes_cambio (creado_en) WHERE estado = 'PENDIENTE';
CREATE TRIGGER solicitudes_auditoria AFTER INSERT OR UPDATE OR DELETE ON agenda.solicitudes_cambio
  FOR EACH ROW EXECUTE FUNCTION seguridad.tg_auditar();

-- -----------------------------------------------------------------------------
-- Vistas de consulta
-- -----------------------------------------------------------------------------
CREATE VIEW matriculas.v_saldo_sesiones AS
SELECT m.id AS matricula_id,
       m.paciente_id,
       m.programa_id,
       m.estado,
       m.sesiones_contratadas,
       count(p.id) FILTER (WHERE p.asistencia IN ('ASISTIO', 'FALTA'))                      AS sesiones_consumidas,
       count(p.id) FILTER (WHERE p.asistencia = 'PENDIENTE')                                AS sesiones_agendadas,
       m.sesiones_contratadas
         - count(p.id) FILTER (WHERE p.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA', 'FALTA_JUSTIFICADA')) AS sesiones_por_agendar
FROM matriculas.matriculas m
LEFT JOIN agenda.participantes p ON p.matricula_id = m.id
GROUP BY m.id;
COMMENT ON VIEW matriculas.v_saldo_sesiones IS 'Sesiones contratadas, consumidas, agendadas y por agendar de cada matrícula, calculadas desde la asistencia.';

CREATE VIEW agenda.v_sesiones_detalle AS
SELECT s.id,
       s.inicio AT TIME ZONE se.zona_horaria AS inicio_local,
       s.fin AT TIME ZONE se.zona_horaria    AS fin_local,
       se.nombre                              AS sede,
       pr.nombres || ' ' || pr.apellidos      AS terapeuta,
       pg.nombre                              AS programa,
       g.codigo                               AS grupo,
       s.tipo,
       s.estado,
       s.cupo_maximo,
       (SELECT count(*) FROM agenda.participantes p
         WHERE p.sesion_id = s.id AND p.asistencia NOT IN ('CANCELADA', 'REPROGRAMADA')) AS ocupados
FROM agenda.sesiones s
JOIN organizacion.sedes se ON se.id = s.sede_id
JOIN personas.profesionales pr ON pr.id = s.profesional_id
LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
LEFT JOIN agenda.grupos g ON g.id = s.grupo_id;
COMMENT ON VIEW agenda.v_sesiones_detalle IS 'Sesiones con nombres legibles y ocupación (x de cupo), en hora local de la sede.';
