-- =============================================================================
-- 140 · Corrección de la auditoría (17/10/2026)
-- Los disparadores de auditoría sin columnas excluidas recibían TG_ARGV nulo y
-- el FOREACH fallaba: cualquier alta o edición de esas tablas daba error.
-- (Los datos de prueba no lo mostraban porque se cargan sin auditoría.)
-- =============================================================================

CREATE OR REPLACE FUNCTION seguridad.tg_auditar() RETURNS trigger
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
  IF TG_NARGS > 0 THEN
    FOREACH v_col IN ARRAY TG_ARGV LOOP
      v_antes := v_antes - v_col;
      v_despues := v_despues - v_col;
    END LOOP;
  END IF;
  INSERT INTO seguridad.bitacora (usuario_id, accion, esquema, tabla, registro_id, antes, despues)
  VALUES (
    comun.usuario_actual(),
    CASE TG_OP WHEN 'INSERT' THEN 'CREAR' WHEN 'UPDATE' THEN 'EDITAR' ELSE 'ELIMINAR' END,
    TG_TABLE_SCHEMA, TG_TABLE_NAME,
    coalesce(v_despues, v_antes) ->> 'id',
    v_antes, v_despues);
  RETURN NULL;
END $$;
