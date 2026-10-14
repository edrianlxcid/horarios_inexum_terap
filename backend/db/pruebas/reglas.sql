-- =============================================================================
-- Prueba de las reglas que protege la base de datos.
-- Crea un escenario mínimo, intenta romper cada regla y verifica que la base
-- lo rechace. Todo ocurre dentro de una transacción que se deshace al final.
--   psql -d ismart_horarios -v ON_ERROR_STOP=1 -f db/pruebas/reglas.sql
-- =============================================================================
BEGIN;
SET LOCAL app.omitir_auditoria = 'on';
SET LOCAL TimeZone = 'America/Guayaquil';

CREATE TEMP TABLE resultados (regla text, ok boolean, detalle text) ON COMMIT DROP;

-- Ejecuta una sentencia que DEBE fallar y anota el resultado.
CREATE FUNCTION pg_temp.debe_fallar(p_regla text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO resultados VALUES (p_regla, false, 'La base aceptó algo que debía rechazar');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultados VALUES (p_regla, true, SQLERRM);
  END;
END $$;

-- Ejecuta una sentencia que DEBE funcionar.
CREATE FUNCTION pg_temp.debe_funcionar(p_regla text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO resultados VALUES (p_regla, true, 'Aceptado');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultados VALUES (p_regla, false, SQLERRM);
  END;
END $$;

-- Escenario ---------------------------------------------------------------
INSERT INTO organizacion.paises VALUES ('ZZ', 'Prueba') ON CONFLICT DO NOTHING;
INSERT INTO organizacion.provincias VALUES (9901, 'ZZ', 'Prueba') ON CONFLICT DO NOTHING;
INSERT INTO organizacion.cantones VALUES (990101, 9901, 'Prueba') ON CONFLICT DO NOTHING;
INSERT INTO organizacion.parroquias VALUES (99010101, 990101, 'Prueba') ON CONFLICT DO NOTHING;

INSERT INTO organizacion.sedes (id, codigo, nombre, parroquia_id)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'PRUEBA_SEDE', 'Sede de prueba', 99010101);
INSERT INTO organizacion.feriados (fecha, nombre) VALUES ('2030-01-07', 'Feriado de prueba');

INSERT INTO catalogo.areas (id, codigo, nombre) VALUES ('00000000-0000-0000-0000-0000000000b1', 'PRUEBA_AREA', 'Área de prueba');
INSERT INTO catalogo.sub_areas (id, area_id, codigo, nombre) VALUES
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b1', 'PRUEBA_ESP', 'Especialidad de prueba'),
  ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000b1', 'PRUEBA_OTRA', 'Otra especialidad');
INSERT INTO catalogo.tipos_programa (id, codigo, nombre, patron) VALUES
  ('00000000-0000-0000-0000-0000000000b4', 'PRUEBA_TIPO', 'Tipo de prueba', 'SEMANAL_FIJO');
INSERT INTO catalogo.programas (id, area_id, tipo_programa_id, sub_area_requerida_id, codigo, nombre,
                                total_sesiones, sesiones_por_semana, modalidad, cupo_maximo)
VALUES ('00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b4',
        '00000000-0000-0000-0000-0000000000b2', 'PRUEBA_GRUPAL', 'Programa grupal de prueba', 2, 2, 'GRUPAL', 2);

INSERT INTO personas.profesionales (id, cedula, nombres, apellidos, profesion) VALUES
  ('00000000-0000-0000-0000-0000000000c1', '9900000001', 'Ana', 'Prueba', 'Terapeuta'),
  ('00000000-0000-0000-0000-0000000000c2', '9900000002', 'Luis', 'SinEspecialidad', 'Terapeuta');
INSERT INTO personas.profesional_sub_areas VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b2', true),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b3', true);
INSERT INTO agenda.jornadas (profesional_id, sede_id, dia_semana, hora_inicio, hora_fin, vigente_desde)
SELECT p, '00000000-0000-0000-0000-0000000000a1', d, '08:00', '17:00', '2030-01-01'
FROM unnest(ARRAY['00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2']::uuid[]) p,
     generate_series(1, 6) d;
INSERT INTO agenda.pausas (profesional_id, dia_semana, hora_inicio, hora_fin, tipo, vigente_desde)
SELECT '00000000-0000-0000-0000-0000000000c1', d, '13:00', '14:00', 'ALMUERZO', '2030-01-01' FROM generate_series(1, 6) d;

INSERT INTO personas.representantes (id, cedula, nombres, apellidos) VALUES
  ('00000000-0000-0000-0000-0000000000d1', '9900000011', 'Rosa', 'Prueba');
INSERT INTO personas.pacientes (id, codigo_historia, nombres, apellidos, fecha_nacimiento, sede_principal_id, estado) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'HC-99001', 'Niño', 'Uno', '2020-01-01', '00000000-0000-0000-0000-0000000000a1', 'ACTIVO'),
  ('00000000-0000-0000-0000-0000000000e2', 'HC-99002', 'Niña', 'Dos', '2020-01-01', '00000000-0000-0000-0000-0000000000a1', 'ACTIVO'),
  ('00000000-0000-0000-0000-0000000000e3', 'HC-99003', 'Niño', 'Tres', '2020-01-01', '00000000-0000-0000-0000-0000000000a1', 'ACTIVO');
INSERT INTO matriculas.contratos (id, codigo, representante_id, sede_id, tipo, valor_total, fecha_firma, vigente_desde, vigente_hasta)
VALUES ('00000000-0000-0000-0000-0000000000f1', 'PRB-0001', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1',
        'CONTADO', 100, '2030-01-01', '2030-01-01', '2030-12-31');
INSERT INTO matriculas.matriculas (id, contrato_id, paciente_id, programa_id, fecha_inicio, sesiones_contratadas)
SELECT ('00000000-0000-0000-0000-0000000001f' || n)::uuid, '00000000-0000-0000-0000-0000000000f1',
       ('00000000-0000-0000-0000-0000000000e' || n)::uuid, '00000000-0000-0000-0000-0000000000b5', '2030-01-01', 2
FROM generate_series(1, 3) n;

-- 2030-01-08 es martes; 2030-01-06 es domingo; 2030-01-07 es el feriado de prueba.
INSERT INTO agenda.sesiones (id, sede_id, profesional_id, programa_id, tipo, inicio, fin, cupo_maximo) VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1',
   '00000000-0000-0000-0000-0000000000b5', 'PROGRAMA', '2030-01-08 09:00', '2030-01-08 10:00', 2);

-- Pruebas -----------------------------------------------------------------
SELECT pg_temp.debe_fallar('1. Terapeuta con dos sesiones superpuestas',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, programa_id, tipo, inicio, fin, cupo_maximo)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1',
             '00000000-0000-0000-0000-0000000000b5', 'PROGRAMA', '2030-01-08 09:30', '2030-01-08 10:30', 1)$q$);

SELECT pg_temp.debe_fallar('No se agenda en domingo',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, tipo, inicio, fin)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'VALORACION', '2030-01-06 09:00', '2030-01-06 10:00')$q$);

SELECT pg_temp.debe_fallar('No se agenda en feriado',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, tipo, inicio, fin)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'VALORACION', '2030-01-07 09:00', '2030-01-07 10:00')$q$);

SELECT pg_temp.debe_fallar('No se agenda fuera de la jornada',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, tipo, inicio, fin)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'VALORACION', '2030-01-08 18:00', '2030-01-08 19:00')$q$);

SELECT pg_temp.debe_fallar('No se agenda en el almuerzo',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, tipo, inicio, fin)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'VALORACION', '2030-01-08 13:00', '2030-01-08 14:00')$q$);

SELECT pg_temp.debe_fallar('Terapeuta sin la especialidad del programa',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, programa_id, tipo, inicio, fin)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c2',
             '00000000-0000-0000-0000-0000000000b5', 'PROGRAMA', '2030-01-08 09:00', '2030-01-08 10:00')$q$);

SELECT pg_temp.debe_fallar('Cupo de la sesión mayor que el del programa',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, programa_id, tipo, inicio, fin, cupo_maximo)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1',
             '00000000-0000-0000-0000-0000000000b5', 'PROGRAMA', '2030-01-08 11:00', '2030-01-08 12:00', 9)$q$);

SELECT pg_temp.debe_fallar('Valoración grupal',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, tipo, inicio, fin, cupo_maximo)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'VALORACION', '2030-01-08 15:00', '2030-01-08 16:00', 3)$q$);

SELECT pg_temp.debe_funcionar('Agregar dos pacientes a una sesión de cupo 2',
  $q$INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id, numero_sesion) VALUES
     ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000001f1', 1),
     ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000001f2', 1)$q$);

SELECT pg_temp.debe_fallar('3. Tercer paciente en una sesión de cupo 2',
  $q$INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id)
     VALUES ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000001f3')$q$);

SELECT pg_temp.debe_fallar('5. Mismo paciente dos veces en la misma sesión',
  $q$INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id)
     VALUES ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000001f1')$q$);

-- Otro terapeuta habilitado a la misma hora, para probar el choque del paciente.
INSERT INTO personas.profesional_sub_areas VALUES ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b2', false);
INSERT INTO agenda.sesiones (id, sede_id, profesional_id, programa_id, tipo, inicio, fin, cupo_maximo) VALUES
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c2',
   '00000000-0000-0000-0000-0000000000b5', 'PROGRAMA', '2030-01-08 09:00', '2030-01-08 10:00', 2);

SELECT pg_temp.debe_fallar('2. Paciente en dos sesiones a la misma hora',
  $q$INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id)
     VALUES ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000001f1')$q$);

SELECT pg_temp.debe_fallar('6. Sesión que termina antes de empezar',
  $q$INSERT INTO agenda.sesiones (sede_id, profesional_id, tipo, inicio, fin)
     VALUES ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'VALORACION', '2030-01-09 10:00', '2030-01-09 09:00')$q$);

SELECT pg_temp.debe_fallar('7. Estado escrito con error',
  $q$UPDATE agenda.sesiones SET estado = 'REALIZDA' WHERE id = '00000000-0000-0000-0000-000000000101'$q$);

-- Saldo: la matrícula 3 tiene 2 sesiones; se usan ambas y la tercera debe fallar.
INSERT INTO agenda.sesiones (id, sede_id, profesional_id, programa_id, tipo, inicio, fin, cupo_maximo)
SELECT ('00000000-0000-0000-0000-00000000020' || n)::uuid, '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1',
       '00000000-0000-0000-0000-0000000000b5', 'PROGRAMA', ('2030-01-1' || n || ' 15:00')::timestamptz, ('2030-01-1' || n || ' 16:00')::timestamptz, 1
FROM generate_series(0, 2) n;
INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id) VALUES
  ('00000000-0000-0000-0000-000000000200', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000001f3'),
  ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000001f3');
SELECT pg_temp.debe_fallar('Matrícula sin sesiones disponibles',
  $q$INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id)
     VALUES ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000001f3')$q$);

UPDATE matriculas.contratos SET estado = 'VENCIDO' WHERE id = '00000000-0000-0000-0000-0000000000f1';
SELECT pg_temp.debe_fallar('8. Agendar con el contrato vencido',
  $q$INSERT INTO agenda.participantes (sesion_id, paciente_id, matricula_id)
     VALUES ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000001f2')$q$);

INSERT INTO clinico.notas_sesion (id, participante_id, profesional_id, contenido, firmada_en)
SELECT '00000000-0000-0000-0000-000000000301', p.id, '00000000-0000-0000-0000-0000000000c1', comun.cifrar('nota', 'llave'), now()
FROM agenda.participantes p WHERE p.sesion_id = '00000000-0000-0000-0000-000000000101' LIMIT 1;
SELECT pg_temp.debe_fallar('9. Editar una nota firmada',
  $q$UPDATE clinico.notas_sesion SET resumen_familia = 'cambio' WHERE id = '00000000-0000-0000-0000-000000000301'$q$);

INSERT INTO seguridad.usuarios (id, email, password_hash, nombres, apellidos)
VALUES ('00000000-0000-0000-0000-000000000401', 'terapeuta@prueba.test', 'x', 'Ana', 'Prueba');
INSERT INTO seguridad.usuario_roles (usuario_id, rol_id)
SELECT '00000000-0000-0000-0000-000000000401', id FROM seguridad.roles WHERE codigo = 'TERAPEUTA';
SELECT pg_temp.debe_fallar('Un terapeuta no puede clasificar la demanda',
  $q$INSERT INTO personas.clasificaciones_demanda (paciente_id, nivel_id, motivo, clasificado_por)
     SELECT '00000000-0000-0000-0000-0000000000e1', id, 'Necesita contención', '00000000-0000-0000-0000-000000000401'
     FROM personas.niveles_demanda WHERE codigo = 'ALTA'$q$);

SELECT pg_temp.debe_fallar('Grupo con cupo mayor que el del programa',
  $q$INSERT INTO agenda.grupos (codigo, programa_id, sede_id, profesional_id, cupo_maximo)
     VALUES ('G-9901', '00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 6)$q$);

-- Resultado ---------------------------------------------------------------
\echo
\echo 'Resultado de las pruebas de reglas'
SELECT CASE WHEN ok THEN 'OK   ' ELSE 'FALLA' END AS estado, regla, detalle FROM resultados;
SELECT count(*) FILTER (WHERE ok) || ' de ' || count(*) || ' pruebas superadas' AS resumen FROM resultados;

ROLLBACK;
