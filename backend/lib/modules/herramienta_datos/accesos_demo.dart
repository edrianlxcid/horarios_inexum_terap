import 'package:backend/core/db/base_datos.dart';

/// Usuarios de prueba por empresa y rol, para entrar rápido a cada interfaz
/// durante el desarrollo. Elige terapeutas con sesiones hoy y familias con
/// evaluaciones pendientes o sesiones próximas, para que haya qué probar.
class AccesosDemo {
  AccesosDemo(this._db);

  final BaseDatos _db;

  Future<List<Map<String, Object?>>> listar() async {
    final empresas = await _db.sinEmpresa(
      (tx) => filas(tx, 'SELECT id::text, nombre, rubro FROM organizacion.empresas WHERE activo ORDER BY empresa_matriz_id NULLS FIRST, nombre'),
    );
    final resultado = <Map<String, Object?>>[];
    for (final e in empresas) {
      final usuarios = await _db.enEmpresa(e['id'] as String, (tx) => filas(tx, '''
        WITH roles AS (
          SELECT DISTINCT ON (u.id, r.codigo)
                 u.id AS usuario_id, u.email, u.nombres || ' ' || u.apellidos AS nombre, r.codigo AS rol, r.nivel,
                 concat_ws(' · ', se.nombre, ar.nombre) AS alcance,
                 CASE r.codigo
                   WHEN 'TERAPEUTA' THEN (SELECT count(*) FROM agenda.sesiones s JOIN personas.profesionales p ON p.id = s.profesional_id
                                          WHERE p.usuario_id = u.id AND s.inicio >= now() AND s.inicio < now() + interval '7 days')
                   WHEN 'REPRESENTANTE' THEN (
                     SELECT count(*) * 10 + (SELECT count(*) FROM agenda.participantes x JOIN agenda.sesiones s ON s.id = x.sesion_id
                                             JOIN personas.paciente_representantes pr2 ON pr2.paciente_id = x.paciente_id
                                             WHERE pr2.representante_id = rep.id AND s.inicio > now())
                     FROM desempeno.v_evaluaciones_pendientes ev
                     JOIN personas.paciente_representantes pr ON pr.paciente_id = ev.paciente_id
                     WHERE pr.representante_id = rep.id)
                   ELSE 0 END AS relevancia
          FROM seguridad.usuario_roles ur
          JOIN seguridad.usuarios u ON u.id = ur.usuario_id
          JOIN seguridad.roles r ON r.id = ur.rol_id
          LEFT JOIN organizacion.sedes se ON se.id = ur.sede_id
          LEFT JOIN catalogo.areas ar ON ar.id = ur.area_id
          LEFT JOIN personas.representantes rep ON rep.usuario_id = u.id
          ORDER BY u.id, r.codigo
        ), ranking AS (
          SELECT *, row_number() OVER (PARTITION BY rol ORDER BY relevancia DESC, email) AS n FROM roles
        )
        SELECT usuario_id::text, email, nombre, rol, alcance, relevancia::int FROM ranking
        WHERE n <= CASE WHEN rol IN ('TERAPEUTA', 'REPRESENTANTE') THEN 3 ELSE 6 END
        ORDER BY nivel DESC, relevancia DESC, email'''));
      resultado.add({'empresa_id': e['id'], 'empresa': e['nombre'], 'rubro': e['rubro'], 'usuarios': usuarios});
    }
    return resultado;
  }
}
