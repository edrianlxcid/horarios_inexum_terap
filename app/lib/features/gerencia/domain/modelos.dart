class Indicador {
  const Indicador({required this.codigo, required this.nombre, required this.descripcion, required this.formula, required this.unidad, required this.dimension});

  factory Indicador.fromJson(Map<String, dynamic> j) => Indicador(
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        descripcion: j['descripcion'] as String,
        formula: j['formula'] as String,
        unidad: j['unidad'] as String,
        dimension: j['dimension'] as String,
      );

  final String codigo, nombre, descripcion, formula, unidad, dimension;

  /// Porcentajes y puntajes se promedian entre sedes; cantidades se suman.
  bool get sePromedia => unidad == 'PORCENTAJE' || unidad == 'PUNTAJE';
}

class ValorIndicador {
  const ValorIndicador({required this.codigo, required this.valor, this.sede, this.area, this.detalle});

  factory ValorIndicador.fromJson(Map<String, dynamic> j) => ValorIndicador(
        codigo: j['codigo'] as String,
        valor: (j['valor'] as num).toDouble(),
        sede: j['sede'] as String?,
        area: j['area'] as String?,
        detalle: j['detalle'] as String?,
      );

  final String codigo;
  final double valor;
  final String? sede, area, detalle;

  String get etiqueta => [?detalle, ?sede, ?area].join(' · ');
}

class PanelGerencia {
  const PanelGerencia({required this.fecha, required this.indicadores, required this.valores, required this.series, required this.metas});

  factory PanelGerencia.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) => (j[k] as List).cast<Map<String, dynamic>>();
    final series = <String, List<double>>{};
    for (final s in l('series')) {
      series.putIfAbsent(s['codigo'] as String, () => []).add((s['valor'] as num).toDouble());
    }
    return PanelGerencia(
      fecha: j['fecha'] as String,
      indicadores: [for (final i in l('indicadores')) Indicador.fromJson(i)],
      valores: [for (final v in l('valores')) ValorIndicador.fromJson(v)],
      series: series,
      metas: l('metas'),
    );
  }

  final String fecha;
  final List<Indicador> indicadores;
  final List<ValorIndicador> valores;
  final Map<String, List<double>> series;
  final List<Map<String, dynamic>> metas;

  List<ValorIndicador> valoresDe(String codigo) => valores.where((v) => v.codigo == codigo).toList();

  double? total(Indicador i) {
    final vs = valoresDe(i.codigo);
    if (vs.isEmpty) return null;
    final suma = vs.fold<double>(0, (a, v) => a + v.valor);
    return i.sePromedia ? suma / vs.length : suma;
  }
}
