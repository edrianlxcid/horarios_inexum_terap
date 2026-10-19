// Perfiles de las empresas ficticias que carga la semilla.
// La matriz replica iSmart Salud; la sucursal es un EJEMPLO de empresa con
// otro rubro que comparte el sistema pero no los datos.

/// Definición de un programa de ejemplo.
class ProgDef {
  const ProgDef(this.codigo, this.nombre, this.area, this.tipo, this.sub, this.total, this.meses, this.porSemana,
      this.modalidad, this.entrega, this.cupo, this.requiereValoracion, this.antesEvaluacion, this.precio, this.fases,
      {this.duracion = 60});
  final String codigo, nombre, area, tipo, sub, modalidad, entrega;
  final int total, cupo, antesEvaluacion;
  final int? meses, porSemana;
  final bool requiereValoracion;
  final double precio;
  final List<(String, int, String?)> fases;

  /// Minutos de cada sesión (Neuro y Terapia de lenguaje: 45).
  final int duracion;
}

class SedeDef {
  const SedeDef(this.codigo, this.nombre, this.parroquiaId, this.parroquia, this.direccion);
  final String codigo, nombre, parroquia, direccion;
  final int parroquiaId;
}

/// Coordinador: sedes por índice (vacío = todas) y área (null = todas).
class CoordDef {
  const CoordDef(this.prefijo, this.sedes, this.area);
  final String prefijo;
  final List<int> sedes;
  final String? area;
}

class PerfilEmpresa {
  const PerfilEmpresa({
    required this.codigo,
    required this.nombre,
    required this.rubro,
    required this.color,
    required this.esMatriz,
    required this.provincia,
    required this.canton,
    required this.ruc,
    required this.sedes,
    required this.pesosSedes,
    required this.areas,
    required this.subAreas,
    required this.programas,
    required this.programaValoracion,
    required this.subValoracion,
    required this.plantillaTerapeutas,
    required this.profesiones,
    required this.familias,
    required this.familiasConDosRepresentantes,
    required this.pacientes,
    required this.pesosProgramas,
    required this.edades,
    required this.combinaciones,
    required this.prefijosContrato,
    required this.gerentes,
    required this.administradores,
    required this.coordinadores,
    required this.dominio,
    required this.feriadosLocales,
    this.minutosTurno = const {},
  });

  final String codigo, nombre, rubro, color;
  final bool esMatriz;
  final (int id, String nombre) provincia;
  final (int id, String nombre) canton;
  final String ruc;
  final List<SedeDef> sedes;
  final List<int> pesosSedes;
  final Map<String, String> areas;
  final Map<String, (String area, String nombre)> subAreas;
  final List<ProgDef> programas;
  final String programaValoracion;
  final String subValoracion;
  final List<List<String>> plantillaTerapeutas;
  final Map<String, String> profesiones;
  final int familias, familiasConDosRepresentantes, pacientes;
  final Map<String, int> pesosProgramas;
  final Map<String, (int, int)> edades;
  final Map<String, String> combinaciones;
  final Map<String, String> prefijosContrato;
  final int gerentes, administradores;
  final List<CoordDef> coordinadores;
  final String dominio;
  final Map<String, String> feriadosLocales;

  /// Turno de la agenda por especialidad (las que no aparecen: 60 minutos).
  final Map<String, int> minutosTurno;
}

const perfilMatriz = PerfilEmpresa(
  codigo: 'ISMART',
  nombre: 'iSmart Salud',
  rubro: 'Neuro estimulación y Estimulación temprana',
  color: '#1D5F8A',
  esMatriz: true,
  provincia: (17, 'Pichincha'),
  canton: (1701, 'Quito'),
  ruc: '9900000000001',
  sedes: [
    SedeDef('VILLAFLORA', 'Villaflora', 170150, 'La Magdalena', 'Av. Maldonado S10-45 y Gatazo'),
    SedeDef('NORTE', 'Quito Norte', 170157, 'Kennedy', 'Av. De la Prensa N52-110'),
    SedeDef('TUMBACO', 'Tumbaco', 170184, 'Tumbaco', 'Av. Interoceánica km 14'),
  ],
  pesosSedes: [40, 35, 25],
  areas: {'NEURO': 'Neuro estimulación', 'ESTIMULACION_TEMPRANA': 'Estimulación temprana'},
  subAreas: {
    'VALORACION': ('NEURO', 'Valoración'),
    'TOMATIS': ('NEURO', 'Método Tomatis'),
    'TERAPIA_LENGUAJE': ('NEURO', 'Terapia de lenguaje'),
    'TERAPIA_OCUPACIONAL': ('NEURO', 'Terapia ocupacional'),
    'PSICOLOGIA': ('NEURO', 'Psicología infantil'),
    'ESTIMULACION_TEMPRANA': ('ESTIMULACION_TEMPRANA', 'Estimulación temprana'),
  },
  programas: [
    ProgDef('VALORACION_INICIAL', 'Valoración inicial', 'NEURO', 'VALORACION', 'VALORACION', 4, null, null,
        'INDIVIDUAL', 'PRESENCIAL', 1, false, 0, 60, []),
    ProgDef('TERAPIAS_ESPECIFICAS', 'Terapias específicas', 'NEURO', 'SEMANAL', 'TOMATIS', 32, 4, 2,
        'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 1280, [('F1', 12, null), ('F2', 10, null), ('F3 - Integraciones', 10, 'TERAPIA_OCUPACIONAL')], duracion: 45),
    ProgDef('TERAPIA_LENGUAJE', 'Terapia de lenguaje', 'NEURO', 'SEMANAL', 'TERAPIA_LENGUAJE', 24, 4, 2,
        'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 720, [('Fase 1', 12, null), ('Fase 2', 12, null)], duracion: 45),
    ProgDef('TERAPIA_OCUPACIONAL_GRUPAL', 'Terapia ocupacional grupal', 'NEURO', 'SEMANAL', 'TERAPIA_OCUPACIONAL', 24, 3, 2,
        'GRUPAL', 'PRESENCIAL', 5, true, 1, 480, [], duracion: 45),
    ProgDef('TOMATIS_INTENSIVO', 'Tomatis intensivo', 'NEURO', 'INTENSIVO', 'TOMATIS', 15, 1, 5,
        'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 900, [], duracion: 45),
    ProgDef('PSICOLOGIA_INFANTIL', 'Psicología infantil', 'NEURO', 'SEMANAL', 'PSICOLOGIA', 10, 3, 1,
        'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 350, [], duracion: 45),
    ProgDef('ESTIMULACION_TEMPRANA', 'Estimulación temprana grupal', 'ESTIMULACION_TEMPRANA', 'SEMANAL', 'ESTIMULACION_TEMPRANA', 24, 3, 2,
        'GRUPAL', 'PRESENCIAL', 5, false, 1, 420, []),
    ProgDef('ESTIMULACION_TEMPRANA_INDIVIDUAL', 'Estimulación temprana individual', 'ESTIMULACION_TEMPRANA', 'SEMANAL', 'ESTIMULACION_TEMPRANA', 16, 4, 1,
        'INDIVIDUAL', 'PRESENCIAL', 1, false, 1, 380, []),
  ],
  programaValoracion: 'VALORACION_INICIAL',
  subValoracion: 'VALORACION',
  plantillaTerapeutas: [
    ['VALORACION', 'PSICOLOGIA'], ['VALORACION', 'TERAPIA_LENGUAJE'], ['TOMATIS'], ['TOMATIS', 'TERAPIA_OCUPACIONAL'],
    ['TERAPIA_LENGUAJE'], ['TERAPIA_LENGUAJE'], ['TERAPIA_OCUPACIONAL'], ['TERAPIA_OCUPACIONAL'],
    ['PSICOLOGIA'], ['ESTIMULACION_TEMPRANA'], ['ESTIMULACION_TEMPRANA'], ['ESTIMULACION_TEMPRANA'],
  ],
  profesiones: {
    'VALORACION': 'Psicóloga clínica', 'TOMATIS': 'Terapeuta Tomatis', 'TERAPIA_LENGUAJE': 'Terapeuta de lenguaje',
    'TERAPIA_OCUPACIONAL': 'Terapeuta ocupacional', 'PSICOLOGIA': 'Psicóloga infantil',
    'ESTIMULACION_TEMPRANA': 'Estimuladora temprana',
  },
  familias: 175,
  familiasConDosRepresentantes: 30,
  pacientes: 255,
  pesosProgramas: {
    'TERAPIAS_ESPECIFICAS': 18, 'TERAPIA_LENGUAJE': 18, 'TERAPIA_OCUPACIONAL_GRUPAL': 12, 'TOMATIS_INTENSIVO': 6,
    'PSICOLOGIA_INFANTIL': 10, 'ESTIMULACION_TEMPRANA': 20, 'ESTIMULACION_TEMPRANA_INDIVIDUAL': 16,
  },
  edades: {
    'TERAPIAS_ESPECIFICAS': (3, 10), 'TERAPIA_LENGUAJE': (3, 9), 'TERAPIA_OCUPACIONAL_GRUPAL': (4, 9),
    'TOMATIS_INTENSIVO': (4, 12), 'PSICOLOGIA_INFANTIL': (5, 13), 'ESTIMULACION_TEMPRANA': (1, 3),
    'ESTIMULACION_TEMPRANA_INDIVIDUAL': (0, 2),
  },
  combinaciones: {
    'TERAPIA_LENGUAJE': 'TERAPIA_OCUPACIONAL_GRUPAL',
    'TERAPIAS_ESPECIFICAS': 'PSICOLOGIA_INFANTIL',
    'PSICOLOGIA_INFANTIL': 'TERAPIA_LENGUAJE',
    'TERAPIA_OCUPACIONAL_GRUPAL': 'TERAPIA_LENGUAJE',
    'ESTIMULACION_TEMPRANA_INDIVIDUAL': 'ESTIMULACION_TEMPRANA',
  },
  prefijosContrato: {'NEURO': 'NESC', 'ESTIMULACION_TEMPRANA': 'ESTE'},
  gerentes: 2,
  administradores: 2,
  coordinadores: [
    CoordDef('coord.neuro.norte', [1, 2], 'NEURO'),
    CoordDef('coord.neuro.villaflora', [0], 'NEURO'),
    CoordDef('coord.estimulacion', [], 'ESTIMULACION_TEMPRANA'),
    CoordDef('coord.dos.areas', [0], null),
  ],
  dominio: 'ismart.test',
  feriadosLocales: {'2026-12-04': 'Fundación de Quito'},
  // Terapia de lenguaje atiende en turnos de 45 minutos seguidos; el resto, cada hora.
  minutosTurno: {'TERAPIA_LENGUAJE': 45},
);

/// Sucursal de EJEMPLO con otro rubro, para probar el aislamiento entre empresas.
const perfilSucursal = PerfilEmpresa(
  codigo: 'ISMART_CUENCA',
  nombre: 'iSmart Cuenca (ejemplo)',
  rubro: 'Psicopedagogía y apoyo escolar',
  color: '#2E7D5B',
  esMatriz: false,
  provincia: (1, 'Azuay'),
  canton: (101, 'Cuenca'),
  ruc: '9900000000002',
  sedes: [SedeDef('CENTRO', 'Cuenca Centro', 10150, 'El Sagrario', 'Calle Larga 5-20 y Benigno Malo')],
  pesosSedes: [100],
  areas: {'PSICOPEDAGOGIA': 'Psicopedagogía'},
  subAreas: {
    'EVALUACION_PSP': ('PSICOPEDAGOGIA', 'Evaluación psicopedagógica'),
    'APRENDIZAJE': ('PSICOPEDAGOGIA', 'Terapia de aprendizaje'),
    'LECTOESCRITURA': ('PSICOPEDAGOGIA', 'Lectoescritura'),
  },
  programas: [
    ProgDef('EVALUACION_PSICOPEDAGOGICA', 'Evaluación psicopedagógica', 'PSICOPEDAGOGIA', 'VALORACION', 'EVALUACION_PSP', 2, null, null,
        'INDIVIDUAL', 'PRESENCIAL', 1, false, 0, 50, []),
    ProgDef('APOYO_APRENDIZAJE', 'Apoyo al aprendizaje', 'PSICOPEDAGOGIA', 'SEMANAL', 'APRENDIZAJE', 20, 3, 2,
        'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 500, []),
    ProgDef('TALLER_LECTOESCRITURA', 'Taller de lectoescritura', 'PSICOPEDAGOGIA', 'SEMANAL', 'LECTOESCRITURA', 16, 2, 2,
        'GRUPAL', 'PRESENCIAL', 6, true, 1, 320, []),
  ],
  programaValoracion: 'EVALUACION_PSICOPEDAGOGICA',
  subValoracion: 'EVALUACION_PSP',
  plantillaTerapeutas: [
    ['EVALUACION_PSP', 'APRENDIZAJE'], ['APRENDIZAJE'], ['APRENDIZAJE'],
    ['LECTOESCRITURA'], ['LECTOESCRITURA'], ['APRENDIZAJE', 'LECTOESCRITURA'],
  ],
  profesiones: {
    'EVALUACION_PSP': 'Psicopedagoga', 'APRENDIZAJE': 'Terapeuta de aprendizaje', 'LECTOESCRITURA': 'Docente de lectoescritura',
  },
  familias: 28,
  familiasConDosRepresentantes: 5,
  pacientes: 34,
  pesosProgramas: {'APOYO_APRENDIZAJE': 55, 'TALLER_LECTOESCRITURA': 45},
  edades: {'APOYO_APRENDIZAJE': (6, 12), 'TALLER_LECTOESCRITURA': (6, 10)},
  combinaciones: {'APOYO_APRENDIZAJE': 'TALLER_LECTOESCRITURA'},
  prefijosContrato: {'PSICOPEDAGOGIA': 'CUE'},
  gerentes: 1,
  administradores: 1,
  coordinadores: [CoordDef('coord.cuenca', [], null)],
  dominio: 'cuenca.ismart.test',
  feriadosLocales: {'2027-04-12': 'Fundación de Cuenca'},
);

const perfiles = [perfilMatriz, perfilSucursal];
