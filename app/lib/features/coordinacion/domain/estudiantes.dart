import 'contexto.dart';

/// Filtros del listado de estudiantes. Los nulos significan "todos".
class FiltroEstudiantes {
  const FiltroEstudiantes({this.q = '', this.sede, this.estado, this.profesional, this.programa, this.pagina = 1});

  final String q;
  final String? sede, estado, profesional, programa;
  final int pagina;

  static const estados = ['PROSPECTO', 'ACTIVO', 'CONGELADO', 'GRADUADO', 'RETIRADO'];

  bool get vacio => q.isEmpty && sede == null && estado == null && profesional == null && programa == null;

  /// Cambia un filtro y vuelve a la primera página.
  FiltroEstudiantes con({String? q, String? Function()? sede, String? Function()? estado,
      String? Function()? profesional, String? Function()? programa}) =>
      FiltroEstudiantes(
        q: q ?? this.q,
        sede: sede == null ? this.sede : sede(),
        estado: estado == null ? this.estado : estado(),
        profesional: profesional == null ? this.profesional : profesional(),
        programa: programa == null ? this.programa : programa(),
      );

  FiltroEstudiantes enPagina(int pagina) =>
      FiltroEstudiantes(q: q, sede: sede, estado: estado, profesional: profesional, programa: programa, pagina: pagina);

  Map<String, Object?> get consulta =>
      {'q': q, 'sede': sede, 'estado': estado, 'profesional': profesional, 'programa': programa, 'pagina': pagina};

  @override
  String toString() => consulta.toString();
}

class ContratoResumen {
  const ContratoResumen(this.codigo, this.estado);

  final String codigo, estado;
}

class ProgramaAvance {
  const ProgramaAvance({required this.programa, required this.estado, required this.realizadas, required this.contratadas});

  final String programa, estado;
  final int realizadas, contratadas;
}

/// Una fila del listado: lo justo para ubicar al estudiante y su situación.
class EstudianteFila {
  const EstudianteFila({
    required this.id,
    required this.historia,
    required this.nombres,
    required this.apellidos,
    required this.estado,
    required this.sede,
    required this.contratos,
    required this.programas,
    this.edadMeses,
    this.demanda,
    this.representante,
    this.telefono,
    this.terapeutas,
    this.proximaSesion,
  });

  factory EstudianteFila.fromJson(Map<String, dynamic> j) {
    final rep = j['representante'] as Map<String, dynamic>?;
    return EstudianteFila(
      id: j['id'] as String,
      historia: j['codigo_historia'] as String,
      nombres: j['nombres'] as String,
      apellidos: j['apellidos'] as String,
      estado: j['estado'] as String,
      sede: j['sede'] as String,
      edadMeses: j['edad_meses'] as int?,
      demanda: j['demanda'] as String?,
      representante: rep?['nombre'] as String?,
      telefono: rep?['telefono'] as String?,
      contratos: [for (final c in listaJson(j['contratos'])) ContratoResumen(c['codigo'] as String, c['estado'] as String)],
      programas: [
        for (final p in listaJson(j['programas']))
          ProgramaAvance(
            programa: p['programa'] as String,
            estado: p['estado'] as String,
            realizadas: (p['realizadas'] as num).toInt(),
            contratadas: (p['contratadas'] as num).toInt(),
          ),
      ],
      terapeutas: j['terapeutas'] as String?,
      proximaSesion: j['proxima_sesion'] as String?,
    );
  }

  final String id, historia, nombres, apellidos, estado, sede;
  final int? edadMeses;
  final String? demanda, representante, telefono, terapeutas, proximaSesion;
  final List<ContratoResumen> contratos;
  final List<ProgramaAvance> programas;

  String get nombreCompleto => '$apellidos $nombres';

  /// El contrato vigente, o el más reciente.
  ContratoResumen? get contrato => contratos.isEmpty ? null : contratos.first;
}

class PaginaEstudiantes {
  const PaginaEstudiantes({required this.total, required this.pagina, required this.tamano, required this.filas});

  factory PaginaEstudiantes.fromJson(Map<String, dynamic> j) => PaginaEstudiantes(
        total: j['total'] as int,
        pagina: j['pagina'] as int,
        tamano: j['tamano'] as int,
        filas: [for (final f in listaJson(j['filas'])) EstudianteFila.fromJson(f)],
      );

  final int total, pagina, tamano;
  final List<EstudianteFila> filas;

  int get paginas => total == 0 ? 1 : (total / tamano).ceil();
}
