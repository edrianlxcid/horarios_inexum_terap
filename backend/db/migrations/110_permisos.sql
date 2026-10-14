-- =============================================================================
-- 110 · Permisos
-- 1) Catálogo de permisos de la aplicación por rol.
-- 2) Roles de PostgreSQL con privilegios mínimos:
--    ismart_app      → la API. Lee y escribe, pero no borra datos (solo archiva).
--    ismart_reportes → indicadores. Solo lectura y SIN acceso a datos clínicos.
-- El usuario con contraseña que usa la API se crea fuera de las migraciones
-- (tool/db.dart setup), para que ninguna contraseña quede en el repositorio.
-- =============================================================================

INSERT INTO seguridad.permisos (codigo, modulo, descripcion) VALUES
  ('seguridad.usuarios.gestionar',     'seguridad',      'Crear usuarios y asignar roles'),
  ('seguridad.bitacora.ver',           'seguridad',      'Consultar la bitácora de auditoría'),
  ('organizacion.sedes.gestionar',     'organizacion',   'Sedes, salas y feriados'),
  ('catalogo.programas.gestionar',     'catalogo',       'Programas, reglas, fases y especialidades'),
  ('personas.pacientes.ver',           'personas',       'Ver pacientes (el terapeuta solo los suyos)'),
  ('personas.pacientes.editar',        'personas',       'Registrar y editar pacientes y representantes'),
  ('personas.demanda.clasificar',      'personas',       'Clasificar la demanda de un paciente'),
  ('matriculas.contratos.gestionar',   'matriculas',     'Contratos, matrículas y congelamientos'),
  ('agenda.sesiones.ver',              'agenda',         'Ver la agenda (cada rol con su alcance)'),
  ('agenda.sesiones.gestionar',        'agenda',         'Agendar, mover y cancelar sesiones'),
  ('agenda.asistencia.marcar',         'agenda',         'Marcar asistencia'),
  ('agenda.jornadas.gestionar',        'agenda',         'Jornadas, pausas y ausencias de terapeutas'),
  ('agenda.solicitudes.crear',         'agenda',         'Pedir reprogramación o cancelación'),
  ('agenda.solicitudes.resolver',      'agenda',         'Aprobar o rechazar solicitudes de cambio'),
  ('clinico.notas.escribir',           'clinico',        'Escribir y firmar notas de sesión'),
  ('clinico.notas.ver',                'clinico',        'Leer notas clínicas completas'),
  ('clinico.resumen.ver',              'clinico',        'Ver el resumen para la familia, objetivos y tareas'),
  ('clinico.tareas.gestionar',         'clinico',        'Asignar tareas para casa'),
  ('desempeno.evaluacion.crear',       'desempeno',      'Evaluar al terapeuta'),
  ('desempeno.bonos.ver',              'desempeno',      'Ver bonos de desempeño'),
  ('desempeno.bonos.calcular',         'desempeno',      'Calcular bonos y editar sus tramos'),
  ('reportes.gerencia.ver',            'reportes',       'Panel de Gerencia'),
  ('reportes.coordinacion.ver',        'reportes',       'Panel de Coordinación de su área'),
  ('notificaciones.enviar',            'notificaciones', 'Enviar avisos a familias y equipo');

INSERT INTO seguridad.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM (VALUES
  ('GERENCIA',      ARRAY['seguridad.bitacora.ver', 'personas.demanda.clasificar', 'desempeno.bonos.ver', 'desempeno.bonos.calcular',
                          'reportes.gerencia.ver', 'reportes.coordinacion.ver', 'agenda.sesiones.ver']),
  ('ADMINISTRADOR', ARRAY['seguridad.usuarios.gestionar', 'seguridad.bitacora.ver', 'organizacion.sedes.gestionar',
                          'catalogo.programas.gestionar', 'agenda.jornadas.gestionar', 'personas.demanda.clasificar',
                          'desempeno.bonos.ver', 'agenda.sesiones.ver']),
  ('COORDINADOR',   ARRAY['personas.pacientes.ver', 'personas.pacientes.editar', 'personas.demanda.clasificar',
                          'matriculas.contratos.gestionar', 'agenda.sesiones.ver', 'agenda.sesiones.gestionar',
                          'agenda.asistencia.marcar', 'agenda.solicitudes.crear', 'agenda.solicitudes.resolver',
                          'clinico.notas.ver', 'clinico.resumen.ver', 'reportes.coordinacion.ver', 'notificaciones.enviar']),
  ('TERAPEUTA',     ARRAY['personas.pacientes.ver', 'agenda.sesiones.ver', 'agenda.asistencia.marcar', 'agenda.solicitudes.crear',
                          'clinico.notas.escribir', 'clinico.notas.ver', 'clinico.resumen.ver', 'clinico.tareas.gestionar']),
  ('REPRESENTANTE', ARRAY['agenda.sesiones.ver', 'agenda.solicitudes.crear', 'clinico.resumen.ver', 'desempeno.evaluacion.crear'])
) AS x(rol, permisos)
JOIN seguridad.roles r ON r.codigo = x.rol
JOIN seguridad.permisos p ON p.codigo = ANY (x.permisos);

-- -----------------------------------------------------------------------------
-- Roles de PostgreSQL
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ismart_app') THEN
    CREATE ROLE ismart_app NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ismart_reportes') THEN
    CREATE ROLE ismart_reportes NOLOGIN;
  END IF;
END $$;

-- API: lee y escribe en todos los módulos, sin borrar.
GRANT USAGE ON SCHEMA comun, organizacion, catalogo, seguridad, personas, matriculas,
                      agenda, clinico, desempeno, notificaciones, reportes TO ismart_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA
  comun, organizacion, catalogo, seguridad, personas, matriculas, agenda, clinico, desempeno, notificaciones, reportes
  TO ismart_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA seguridad, reportes TO ismart_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA
  comun, organizacion, catalogo, seguridad, personas, matriculas, agenda, clinico, desempeno, notificaciones, reportes
  TO ismart_app;

-- La bitácora solo admite agregar filas.
REVOKE UPDATE ON seguridad.bitacora FROM ismart_app;

-- Borrar solo se permite en tablas de relación y configuración. El resto se archiva.
GRANT DELETE ON
  seguridad.rol_permisos, seguridad.usuario_roles, seguridad.sesiones_usuario,
  personas.profesional_sub_areas, personas.paciente_representantes,
  agenda.grupo_miembros, agenda.pausas, agenda.ausencias,
  organizacion.feriados, catalogo.programa_fases,
  notificaciones.dispositivos, notificaciones.preferencias,
  desempeno.bono_niveles, reportes.metas, reportes.valores_indicador
  TO ismart_app;

-- Indicadores: solo lectura, y sin datos clínicos ni de seguridad.
GRANT USAGE ON SCHEMA comun, organizacion, catalogo, personas, matriculas, agenda, desempeno, reportes TO ismart_reportes;
GRANT SELECT ON ALL TABLES IN SCHEMA organizacion, catalogo, matriculas, agenda, desempeno, reportes TO ismart_reportes;
GRANT SELECT ON comun.parametros, personas.profesionales, personas.profesional_sub_areas,
                personas.niveles_demanda, personas.clasificaciones_demanda TO ismart_reportes;
-- De los pacientes, solo columnas sin datos personales.
GRANT SELECT (id, sede_principal_id, estado, fecha_nacimiento, sexo, creado_en, archivado_en) ON personas.pacientes TO ismart_reportes;
GRANT INSERT, DELETE ON reportes.valores_indicador TO ismart_reportes;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA reportes TO ismart_reportes;
GRANT EXECUTE ON FUNCTION reportes.calcular_indicadores(date) TO ismart_reportes;

-- Las tablas que se creen en el futuro reciben los mismos permisos.
ALTER DEFAULT PRIVILEGES IN SCHEMA
  comun, organizacion, catalogo, seguridad, personas, matriculas, agenda, clinico, desempeno, notificaciones, reportes
  GRANT SELECT, INSERT, UPDATE ON TABLES TO ismart_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA organizacion, catalogo, matriculas, agenda, desempeno, reportes
  GRANT SELECT ON TABLES TO ismart_reportes;
