import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/modules/coordinacion/alcance.dart';
import 'package:backend/modules/herramienta_datos/modelos.dart';

/// Solicitudes de reprogramación o cancelación que llegan a coordinación.
class SolicitudesCoordinacion {
  SolicitudesCoordinacion(this._db);

  final BaseDatos _db;

  Future<List<Map<String, dynamic>>> lista(Sesion s, {String estado = 'PENDIENTE', String? area}) {
    final a = Alcance.de(s, area: area);
    return _db.conSesion(s, (tx) => filas(tx, '''
      SELECT sc.id::text, sc.tipo, sc.origen, sc.motivo, sc.estado,
             to_char(sc.propuesta_inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS propuesta_inicio,
             to_char(sc.creado_en AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD HH24:MI') AS creado_en,
             pa.nombres || ' ' || pa.apellidos AS paciente, pr.nombres || ' ' || pr.apellidos AS terapeuta,
             to_char(s.inicio AT TIME ZONE 'America/Guayaquil', 'YYYY-MM-DD"T"HH24:MI') AS sesion_inicio,
             pg.nombre AS programa, x.paciente_id::text AS paciente_id
      FROM agenda.solicitudes_cambio sc
      JOIN agenda.participantes x ON x.id = sc.participante_id
      JOIN agenda.sesiones s ON s.id = x.sesion_id
      JOIN personas.pacientes pa ON pa.id = x.paciente_id
      JOIN personas.profesionales pr ON pr.id = s.profesional_id
      LEFT JOIN catalogo.programas pg ON pg.id = s.programa_id
      WHERE sc.estado = @estado:text AND ${Alcance.sedeYArea('s.sede_id', 'pg.area_id')}
      ORDER BY sc.creado_en''', {...a.parametros, 'estado': estado}));
  }

  /// Aprueba o rechaza. Al aprobar, el paciente sale de esa sesión
  /// (cancelada o por reprogramar) y el coordinador agenda la nueva fecha.
  Future<void> resolver(Sesion s, String solicitudId, String estado) {
    if (estado != 'APROBADA' && estado != 'RECHAZADA') throw ErrorDatos(422, 'El estado debe ser APROBADA o RECHAZADA.');
    final a = Alcance.de(s);
    return _db.conSesion(s, (tx) async {
      final sol = await fila(tx, '''
        UPDATE agenda.solicitudes_cambio sc
           SET estado = @e:text, resuelto_por = CAST(@u:text AS uuid), resuelto_en = now()
        FROM agenda.participantes x, agenda.sesiones s, catalogo.programas pg
        WHERE sc.id = CAST(@id:text AS uuid) AND sc.estado = 'PENDIENTE'
          AND x.id = sc.participante_id AND s.id = x.sesion_id AND pg.id = s.programa_id
          AND ${Alcance.sedeYArea('s.sede_id', 'pg.area_id')}
        RETURNING sc.tipo, sc.participante_id::text''', {...a.parametros, 'e': estado, 'u': s.usuarioId, 'id': solicitudId});
      if (sol == null) throw ErrorDatos(404, 'La solicitud no existe, ya fue resuelta o no es de tu coordinación.');
      if (estado == 'APROBADA') {
        await consultar(tx, '''
          UPDATE agenda.participantes SET asistencia = @a:text WHERE id = CAST(@x:text AS uuid) AND asistencia = 'PENDIENTE' ''',
            {'a': sol['tipo'] == 'CANCELAR' ? 'CANCELADA' : 'REPROGRAMADA', 'x': sol['participante_id']});
      }
    });
  }
}
