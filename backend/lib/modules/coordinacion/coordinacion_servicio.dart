import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/agenda_servicio.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/coordinacion/pacientes_servicio.dart';
import 'package:backend/modules/coordinacion/profesionales_servicio.dart';
import 'package:backend/modules/coordinacion/solicitudes_servicio.dart';
import 'package:backend/modules/coordinacion/valoraciones_servicio.dart';

/// Módulo de coordinación. Cada parte vive en su propio servicio y todas se
/// limitan a las sedes y áreas asignadas al coordinador (ver [Alcance]).
class CoordinacionServicio {
  CoordinacionServicio(this._db, String llave)
      : agenda = AgendaCoordinacion(_db),
        pacientes = PacientesCoordinacion(_db, llave),
        profesionales = ProfesionalesCoordinacion(_db),
        solicitudes = SolicitudesCoordinacion(_db),
        valoraciones = ValoracionesCoordinacion(_db);

  final BaseDatos _db;
  final AgendaCoordinacion agenda;
  final PacientesCoordinacion pacientes;
  final ProfesionalesCoordinacion profesionales;
  final SolicitudesCoordinacion solicitudes;
  final ValoracionesCoordinacion valoraciones;

  /// Sedes, áreas, especialidades, terapeutas, programas y niveles de demanda
  /// del alcance, para los filtros y formularios de la pantalla.
  Future<Map<String, Object?>> contexto(Sesion s) {
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async => {
          'alcance': a.pares,
          'puede_registrar_profesionales': s.puede(ProfesionalesCoordinacion.permisoRegistrar),
          'sedes': await filas(tx, '''
            SELECT se.id::text, se.nombre FROM organizacion.sedes se
            WHERE se.activo AND ${Alcance.sede('se.id')} ORDER BY se.nombre''', a.parametros),
          'areas': await filas(tx, '''
            SELECT ar.id::text, ar.nombre FROM catalogo.areas ar
            WHERE ar.activo AND ${Alcance.area('ar.id')} ORDER BY ar.nombre''', a.parametros),
          'especialidades': await filas(tx, '''
            SELECT sa.id::text, sa.nombre, sa.area_id::text FROM catalogo.sub_areas sa
            WHERE sa.activo AND ${Alcance.area('sa.area_id')} ORDER BY sa.nombre''', a.parametros),
          // Quienes valoran entran aunque sean de otra área: también se valora,
          // como excepción, a estudiantes de Estimulación temprana.
          'terapeutas': await filas(tx, '''
            WITH t AS (
              SELECT pr.id, pr.nombres || ' ' || pr.apellidos AS nombre, pr.profesion,
                     agenda.minutos_turno(pr.id) AS minutos_turno,
                     array(SELECT DISTINCT sa.area_id::text FROM personas.profesional_sub_areas psa
                           JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id WHERE psa.profesional_id = pr.id) AS areas,
                     array(SELECT psa.sub_area_id::text FROM personas.profesional_sub_areas psa
                           WHERE psa.profesional_id = pr.id ORDER BY psa.es_principal DESC) AS especialidades,
                     EXISTS (SELECT 1 FROM personas.profesional_sub_areas psa
                             JOIN catalogo.v_especialidades_valoracion ev ON ev.sub_area_id = psa.sub_area_id
                             WHERE psa.profesional_id = pr.id) AS valora,
                     ${Alcance.profesional('pr.id')} AS de_mi_area,
                     EXISTS (SELECT 1 FROM agenda.jornadas j WHERE j.profesional_id = pr.id
                             AND ${Alcance.jornadaVigente('j')} AND ${Alcance.sede('j.sede_id')}) AS de_mi_sede
              FROM personas.profesionales pr
              WHERE pr.activo AND pr.archivado_en IS NULL)
            SELECT id::text, nombre, profesion, minutos_turno, areas, especialidades, valora
            FROM t WHERE de_mi_area OR (valora AND de_mi_sede)
            ORDER BY nombre''', a.parametros),
          // Especialidades que hacen valoraciones iniciales o finales.
          'especialidades_valoracion': await filas(tx, '''
            SELECT sa.id::text, sa.nombre, sa.area_id::text,
                   array_agg(DISTINCT ev.valoracion ORDER BY ev.valoracion) AS tipos
            FROM catalogo.v_especialidades_valoracion ev JOIN catalogo.sub_areas sa ON sa.id = ev.sub_area_id
            WHERE sa.activo GROUP BY sa.id ORDER BY sa.nombre'''),
          'programas': await filas(tx, '''
            SELECT pg.id::text, pg.nombre, pg.area_id::text, pg.modalidad, pg.cupo_maximo, t.es_valoracion, pg.valoracion
            FROM catalogo.programas pg JOIN catalogo.tipos_programa t ON t.id = pg.tipo_programa_id
            WHERE pg.activo AND ${Alcance.area('pg.area_id')} ORDER BY pg.nombre''', a.parametros),
          'niveles_demanda': await filas(tx, 'SELECT id::text, nombre, peso FROM personas.niveles_demanda ORDER BY orden'),
        });
  }
}
