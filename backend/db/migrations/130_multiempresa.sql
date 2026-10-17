-- =============================================================================
-- 130 · Multiempresa (17/10/2026)
-- Una sola base y un solo enlace para la matriz y sus sucursales, que pueden
-- funcionar como empresas distintas (otro rubro). Cada fila de negocio lleva
-- empresa_id y PostgreSQL (Row Level Security) solo deja ver y escribir los
-- datos de la empresa activa en la sesión: app.empresa_id.
-- =============================================================================

CREATE TABLE organizacion.empresas (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z0-9_]+$'),
  nombre           text NOT NULL,
  rubro            text NOT NULL,
  razon_social     text,
  empresa_matriz_id uuid REFERENCES organizacion.empresas,
  color_marca      text CHECK (color_marca ~ '^#[0-9A-Fa-f]{6}$'),
  activo           boolean NOT NULL DEFAULT true,
  creado_en        timestamptz NOT NULL DEFAULT now(),
  actualizado_en   timestamptz NOT NULL DEFAULT now(),
  CHECK (empresa_matriz_id IS DISTINCT FROM id)
);
COMMENT ON TABLE organizacion.empresas IS
  'Matriz y sucursales. Cada sucursal puede tener otro rubro; comparte el sistema pero no los datos.';
COMMENT ON COLUMN organizacion.empresas.empresa_matriz_id IS 'Vacío = es la matriz.';
CREATE TRIGGER empresas_actualizado BEFORE UPDATE ON organizacion.empresas
  FOR EACH ROW EXECUTE FUNCTION comun.tg_actualizado_en();

-- Empresa activa en la sesión. La API la fija al inicio de cada transacción.
CREATE FUNCTION comun.empresa_actual() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.empresa_id', true), '')::uuid
$$;

-- Hace que una restricción UNIQUE existente sea única por empresa.
CREATE FUNCTION comun._unico_por_empresa(p_tabla regclass, p_columnas text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_nombre    text;
  v_nulls     boolean;
  v_columnas  text := array_to_string(ARRAY(SELECT quote_ident(c) FROM unnest(p_columnas) c), ', ');
BEGIN
  SELECT c.conname, pg_get_constraintdef(c.oid) LIKE '%NULLS NOT DISTINCT%'
    INTO v_nombre, v_nulls
  FROM pg_constraint c
  WHERE c.conrelid = p_tabla AND c.contype = 'u'
    AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
         FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey))
        = (SELECT array_agg(x ORDER BY x) FROM unnest(p_columnas) x);
  IF v_nombre IS NOT NULL THEN
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', p_tabla, v_nombre);
  END IF;
  EXECUTE format('ALTER TABLE %s ADD UNIQUE %s (empresa_id, %s)',
                 p_tabla, CASE WHEN v_nulls THEN 'NULLS NOT DISTINCT' ELSE '' END, v_columnas);
END $$;

DO $$
DECLARE
  v_matriz uuid;
  v_tabla  text;
  v_tablas text[] := ARRAY[
    'organizacion.rucs', 'organizacion.sedes', 'organizacion.salas', 'organizacion.feriados',
    'catalogo.areas', 'catalogo.sub_areas', 'catalogo.programas', 'catalogo.programa_fases',
    'seguridad.usuario_roles',
    'personas.profesionales', 'personas.profesional_sub_areas', 'personas.pacientes',
    'personas.representantes', 'personas.paciente_representantes', 'personas.clasificaciones_demanda',
    'matriculas.contratos', 'matriculas.matriculas', 'matriculas.congelamientos',
    'agenda.jornadas', 'agenda.pausas', 'agenda.ausencias', 'agenda.grupos', 'agenda.grupo_miembros',
    'agenda.planes_agenda', 'agenda.sesiones', 'agenda.participantes', 'agenda.solicitudes_cambio',
    'clinico.valoraciones', 'clinico.plantillas_nota', 'clinico.notas_sesion', 'clinico.notas_anexos',
    'clinico.objetivos', 'clinico.avances_objetivo', 'clinico.tareas_casa',
    'desempeno.evaluaciones_terapeuta', 'desempeno.politicas_bono', 'desempeno.bono_niveles',
    'desempeno.bonos_calculados',
    'reportes.metas', 'reportes.valores_indicador'];
BEGIN
  -- La matriz existe siempre; los datos que ya hubiera pasan a ser suyos.
  INSERT INTO organizacion.empresas (codigo, nombre, rubro, color_marca)
  VALUES ('ISMART', 'iSmart Salud', 'Neuro estimulación y Estimulación temprana', '#1D5F8A')
  RETURNING id INTO v_matriz;

  FOREACH v_tabla IN ARRAY v_tablas LOOP
    EXECUTE format('ALTER TABLE %s DISABLE TRIGGER USER', v_tabla);
    EXECUTE format('ALTER TABLE %s ADD COLUMN empresa_id uuid REFERENCES organizacion.empresas', v_tabla);
    EXECUTE format('UPDATE %s SET empresa_id = %L', v_tabla, v_matriz);
    EXECUTE format('ALTER TABLE %s ALTER COLUMN empresa_id SET NOT NULL, '
                   'ALTER COLUMN empresa_id SET DEFAULT comun.empresa_actual()', v_tabla);
    EXECUTE format('ALTER TABLE %s ENABLE TRIGGER USER', v_tabla);
    EXECUTE format('CREATE INDEX ON %s (empresa_id)', v_tabla);
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', v_tabla);
    EXECUTE format('CREATE POLICY aislamiento_empresa ON %s '
                   'USING (empresa_id = comun.empresa_actual()) '
                   'WITH CHECK (empresa_id = comun.empresa_actual())', v_tabla);
    EXECUTE format('COMMENT ON COLUMN %s.empresa_id IS %L', v_tabla,
                   'Empresa dueña del registro. Se llena sola con la empresa activa de la sesión.');
  END LOOP;
END $$;

-- Lo que era único en todo el sistema pasa a ser único dentro de cada empresa.
DO $$
BEGIN
  PERFORM comun._unico_por_empresa('organizacion.sedes', ARRAY['codigo']);
  PERFORM comun._unico_por_empresa('organizacion.feriados', ARRAY['fecha', 'sede_id']);
  PERFORM comun._unico_por_empresa('catalogo.areas', ARRAY['codigo']);
  PERFORM comun._unico_por_empresa('catalogo.sub_areas', ARRAY['codigo']);
  PERFORM comun._unico_por_empresa('catalogo.programas', ARRAY['codigo']);
  PERFORM comun._unico_por_empresa('seguridad.usuario_roles', ARRAY['usuario_id', 'rol_id', 'sede_id', 'area_id']);
  PERFORM comun._unico_por_empresa('personas.profesionales', ARRAY['cedula']);
  PERFORM comun._unico_por_empresa('personas.profesionales', ARRAY['usuario_id']);
  PERFORM comun._unico_por_empresa('personas.representantes', ARRAY['cedula']);
  PERFORM comun._unico_por_empresa('personas.representantes', ARRAY['usuario_id']);
  PERFORM comun._unico_por_empresa('personas.pacientes', ARRAY['codigo_historia']);
  PERFORM comun._unico_por_empresa('personas.pacientes', ARRAY['cedula_huella']);
  PERFORM comun._unico_por_empresa('matriculas.contratos', ARRAY['codigo']);
  PERFORM comun._unico_por_empresa('agenda.grupos', ARRAY['codigo']);
  PERFORM comun._unico_por_empresa('reportes.metas', ARRAY['indicador_id', 'sede_id', 'area_id', 'periodo']);
  PERFORM comun._unico_por_empresa('reportes.valores_indicador',
                                  ARRAY['indicador_id', 'fecha', 'sede_id', 'area_id', 'dimension_id']);
END $$;
DROP FUNCTION comun._unico_por_empresa(regclass, text[]);

-- Las vistas respetan el aislamiento de quien consulta.
ALTER VIEW matriculas.v_saldo_sesiones SET (security_invoker = true);
ALTER VIEW agenda.v_sesiones_detalle SET (security_invoker = true);
ALTER VIEW desempeno.v_evaluaciones_pendientes SET (security_invoker = true);

-- -----------------------------------------------------------------------------
-- Usuarios: la cuenta es una sola para todas las empresas. Cada empresa solo
-- ve a las personas que tienen un rol en ella (y cada uno se ve a sí mismo).
-- -----------------------------------------------------------------------------
ALTER TABLE seguridad.usuarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY usuarios_de_la_empresa ON seguridad.usuarios FOR SELECT
  USING (id = comun.usuario_actual()
         OR EXISTS (SELECT 1 FROM seguridad.usuario_roles ur WHERE ur.usuario_id = usuarios.id));
CREATE POLICY usuarios_editar ON seguridad.usuarios FOR UPDATE
  USING (id = comun.usuario_actual()
         OR EXISTS (SELECT 1 FROM seguridad.usuario_roles ur WHERE ur.usuario_id = usuarios.id));
CREATE POLICY usuarios_crear ON seguridad.usuarios FOR INSERT WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- Funciones del inicio de sesión. Corren con permisos del dueño porque
-- necesitan leer antes de saber a qué empresa pertenece el usuario.
-- -----------------------------------------------------------------------------
CREATE FUNCTION seguridad.credenciales(p_email text)
RETURNS TABLE (usuario_id uuid, password_hash text, activo boolean, bloqueado_hasta timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT u.id, u.password_hash, u.activo AND u.archivado_en IS NULL, u.bloqueado_hasta
  FROM seguridad.usuarios u WHERE lower(u.email) = lower(p_email)
$$;

CREATE FUNCTION seguridad.registrar_intento(p_usuario uuid, p_exitoso boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_exitoso THEN
    UPDATE seguridad.usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso_en = now()
    WHERE id = p_usuario;
  ELSE
    -- 5 intentos fallidos bloquean la cuenta 15 minutos.
    UPDATE seguridad.usuarios
       SET intentos_fallidos = intentos_fallidos + 1,
           bloqueado_hasta = CASE WHEN intentos_fallidos + 1 >= 5 THEN now() + interval '15 minutes' END
     WHERE id = p_usuario;
  END IF;
  INSERT INTO seguridad.bitacora (usuario_id, accion, esquema, tabla, registro_id)
  VALUES (p_usuario, CASE WHEN p_exitoso THEN 'LOGIN' ELSE 'LOGIN_FALLIDO' END, 'seguridad', 'usuarios', p_usuario::text);
END $$;

-- Empresas, roles, alcance y permisos vigentes de un usuario.
CREATE FUNCTION seguridad.accesos(p_usuario uuid)
RETURNS TABLE (
  empresa_id uuid, empresa text, empresa_codigo text, rubro text, color_marca text,
  rol text, nivel smallint, sede_id uuid, sede text, area_id uuid, area text, permisos text[]
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT e.id, e.nombre, e.codigo, e.rubro, e.color_marca,
         r.codigo, r.nivel, ur.sede_id, s.nombre, ur.area_id, a.nombre,
         ARRAY(SELECT p.codigo FROM seguridad.rol_permisos rp
               JOIN seguridad.permisos p ON p.id = rp.permiso_id
               WHERE rp.rol_id = r.id ORDER BY p.codigo)
  FROM seguridad.usuario_roles ur
  JOIN seguridad.usuarios u ON u.id = ur.usuario_id
  JOIN seguridad.roles r ON r.id = ur.rol_id
  JOIN organizacion.empresas e ON e.id = ur.empresa_id
  LEFT JOIN organizacion.sedes s ON s.id = ur.sede_id
  LEFT JOIN catalogo.areas a ON a.id = ur.area_id
  WHERE ur.usuario_id = p_usuario AND u.activo AND u.archivado_en IS NULL AND e.activo
    AND current_date BETWEEN ur.vigente_desde AND coalesce(ur.vigente_hasta, 'infinity'::date)
  ORDER BY e.nombre, r.nivel DESC
$$;

REVOKE ALL ON FUNCTION seguridad.credenciales(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION seguridad.registrar_intento(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION seguridad.accesos(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION seguridad.credenciales(text), seguridad.registrar_intento(uuid, boolean),
  seguridad.accesos(uuid), comun.empresa_actual() TO ismart_app;
GRANT EXECUTE ON FUNCTION comun.empresa_actual() TO ismart_reportes;
GRANT SELECT ON organizacion.empresas TO ismart_app, ismart_reportes;
GRANT SELECT (empresa_id) ON personas.pacientes TO ismart_reportes;
GRANT UPDATE ON organizacion.empresas TO ismart_app;

-- Los indicadores se calculan por empresa con el rol de reportes (sin acceso clínico).
CREATE FUNCTION reportes.calcular_todas_las_empresas(p_fecha date DEFAULT current_date)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_empresa uuid;
  v_total   integer := 0;
BEGIN
  FOR v_empresa IN SELECT id FROM organizacion.empresas WHERE activo LOOP
    PERFORM set_config('app.empresa_id', v_empresa::text, true);
    v_total := v_total + reportes.calcular_indicadores(p_fecha);
  END LOOP;
  RETURN v_total;
END $$;
COMMENT ON FUNCTION reportes.calcular_todas_las_empresas IS
  'Recalcula los indicadores de cada empresa. Debe ejecutarse con el rol ismart_reportes para respetar el aislamiento.';
GRANT EXECUTE ON FUNCTION reportes.calcular_todas_las_empresas(date) TO ismart_reportes;
