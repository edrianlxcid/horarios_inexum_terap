import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/db/base_datos.dart';

/// Panel de Gerencia: indicadores guardados por la base (uno por día),
/// su evolución, las metas del mes y los bonos de desempeño.
class GerenciaServicio {
  GerenciaServicio(this._db);

  final BaseDatos _db;

  /// Indicadores principales cuya evolución se muestra en el panel.
  static const _series = ['SATURACION_SEDE', 'ASISTENCIA_30D', 'PACIENTES_ACTIVOS', 'SESIONES_SEMANA'];

  Future<Map<String, Object?>> panel(Sesion s, {String? fecha}) => _db.conSesion(s, (tx) async {
        final dia = fecha ??
            (await fila(tx, "SELECT coalesce(to_char(max(fecha), 'YYYY-MM-DD'), to_char(current_date, 'YYYY-MM-DD')) AS f "
                    'FROM reportes.valores_indicador'))!['f'] as String;
        final p = {'f': dia, 'series': '{${_series.join(',')}}'};
        return {
          'fecha': dia,
          'indicadores': await filas(tx, '''
            SELECT codigo, nombre, descripcion, formula, unidad, dimension
            FROM reportes.indicadores WHERE activo ORDER BY nombre'''),
          'valores': await filas(tx, '''
            SELECT i.codigo, v.valor::float AS valor, se.nombre AS sede, ar.nombre AS area,
                   CASE i.dimension
                     WHEN 'PROFESIONAL' THEN (SELECT nombres || ' ' || apellidos FROM personas.profesionales WHERE id = v.dimension_id)
                     WHEN 'PROGRAMA' THEN (SELECT nombre FROM catalogo.programas WHERE id = v.dimension_id)
                     WHEN 'SUB_AREA' THEN (SELECT nombre FROM catalogo.sub_areas WHERE id = v.dimension_id)
                   END AS detalle
            FROM reportes.valores_indicador v
            JOIN reportes.indicadores i ON i.id = v.indicador_id
            LEFT JOIN organizacion.sedes se ON se.id = v.sede_id
            LEFT JOIN catalogo.areas ar ON ar.id = v.area_id
            WHERE v.fecha = CAST(@f:text AS date)
            ORDER BY i.codigo, v.valor DESC''', p),
          'series': await filas(tx, '''
            SELECT i.codigo, to_char(v.fecha, 'YYYY-MM-DD') AS fecha,
                   round(CASE WHEN i.unidad IN ('PORCENTAJE', 'PUNTAJE') THEN avg(v.valor) ELSE sum(v.valor) END, 2)::float AS valor
            FROM reportes.valores_indicador v JOIN reportes.indicadores i ON i.id = v.indicador_id
            WHERE i.codigo = ANY (CAST(@series:text AS text[]))
              AND v.fecha BETWEEN CAST(@f:text AS date) - 29 AND CAST(@f:text AS date)
            GROUP BY i.codigo, i.unidad, v.fecha ORDER BY i.codigo, v.fecha''', p),
          'metas': await filas(tx, '''
            SELECT i.codigo, se.nombre AS sede, m.valor_meta::float AS meta
            FROM reportes.metas m JOIN reportes.indicadores i ON i.id = m.indicador_id
            LEFT JOIN organizacion.sedes se ON se.id = m.sede_id
            WHERE m.periodo = date_trunc('month', CAST(@f:text AS date))::date''', p),
        };
      });

  Future<Map<String, Object?>> bonos(Sesion s, {String? periodo}) => _db.conSesion(s, (tx) async {
        final mes = periodo ??
            (await fila(tx, "SELECT coalesce(to_char(max(periodo_inicio), 'YYYY-MM'), to_char(current_date, 'YYYY-MM')) AS m "
                    'FROM desempeno.bonos_calculados'))!['m'] as String;
        return {
          'periodo': mes,
          'periodos': [
            for (final f in await filas(tx, "SELECT DISTINCT to_char(periodo_inicio, 'YYYY-MM') AS m "
                'FROM desempeno.bonos_calculados ORDER BY 1 DESC'))
              f['m'],
          ],
          'bonos': await filas(tx, '''
            SELECT pr.nombres || ' ' || pr.apellidos AS terapeuta, pr.profesion, b.evaluaciones,
                   b.promedio::float AS promedio, b.porcentaje::float AS porcentaje,
                   b.monto::float AS monto, b.monto_posible::float AS monto_posible, pb.nombre AS politica
            FROM desempeno.bonos_calculados b
            JOIN personas.profesionales pr ON pr.id = b.profesional_id
            JOIN desempeno.politicas_bono pb ON pb.id = b.politica_id
            WHERE to_char(b.periodo_inicio, 'YYYY-MM') = @m:text
            ORDER BY b.promedio DESC NULLS LAST''', {'m': mes}),
        };
      });

  /// Recalcula los indicadores de hoy de la empresa activa.
  Future<int> recalcular(Sesion s) => _db.conSesion(s, (tx) async {
        final r = await fila(tx, 'SELECT reportes.calcular_indicadores(current_date) AS n');
        return r!['n'] as int;
      });
}
