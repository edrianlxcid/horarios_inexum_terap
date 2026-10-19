import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/agenda_servicio.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/coordinacion/pacientes_servicio.dart';
import 'package:backend/modules/coordinacion/profesionales_servicio.dart';
import 'package:backend/modules/coordinacion/solicitudes_servicio.dart';

/// Módulo de coordinación. Cada parte vive en su propio servicio y todas se
/// limitan a las sedes y áreas asignadas al coordinador (ver [Alcance]).
class CoordinacionServicio {
  CoordinacionServicio(this._db, String llave)
      : agenda = AgendaCoordinacion(_db),
        pacientes = PacientesCoordinacion(_db, llave),
        profesionales = ProfesionalesCoordinacion(_db),
        solicitudes = SolicitudesCoordinacion(_db);

  final BaseDatos _db;
  final AgendaCoordinacion agenda;
  final PacientesCoordinacion pacientes;
  final ProfesionalesCoordinacion profesionales;
  final SolicitudesCoordinacion solicitudes;

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
          'terapeutas': await filas(tx, '''
            SELECT pr.id::text, pr.nombres || ' ' || pr.apellidos AS nombre, pr.profesion,
                   array(SELECT DISTINCT sa.area_id::text FROM personas.profesional_sub_areas psa
                         JOIN catalogo.sub_areas sa ON sa.id = psa.sub_area_id WHERE psa.profesional_id = pr.id) AS areas
            FROM personas.profesionales pr
            WHERE pr.activo AND pr.archivado_en IS NULL AND ${Alcance.profesional('pr.id')}
            ORDER BY 2''', a.parametros),
          'programas': await filas(tx, '''
            SELECT pg.id::text, pg.nombre, pg.area_id::text, pg.modalidad, pg.cupo_maximo, t.es_valoracion
            FROM catalogo.programas pg JOIN catalogo.tipos_programa t ON t.id = pg.tipo_programa_id
            WHERE pg.activo AND ${Alcance.area('pg.area_id')} ORDER BY pg.nombre''', a.parametros),
          'niveles_demanda': await filas(tx, 'SELECT id::text, nombre, peso FROM personas.niveles_demanda ORDER BY orden'),
        });
  }
}
