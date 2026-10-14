// Generador de datos FICTICIOS para desarrollo.
//
// Arma en memoria una historia coherente de ~500 personas (personal,
// terapeutas, representantes y pacientes) con varios meses de agenda, y luego
// la inserta respetando todas las reglas de la base de datos: jornadas,
// almuerzos, feriados, ausencias, cupos y choques de horario.
//
// Datos ficticios: cédulas con prefijo 99 (provincia inexistente), correos con
// dominio reservado .test y teléfonos con prefijo 0900.

import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import 'textos.dart';

typedef Franja = (int dia, int hora);

class GeneradorSemilla {
  GeneradorSemilla(
    this._db, {
    required this.llave,
    required this.passwordUsuarios,
    int semilla = 20261005,
  }) : _r = Random(semilla);

  final Connection _db;
  final String llave;
  final String passwordUsuarios;
  final Random _r;
  final _uuid = const Uuid();

  /// "Hoy" en hora local de Ecuador, como fecha sin zona horaria.
  final DateTime hoy = _soloFecha(DateTime.now().toUtc().subtract(const Duration(hours: 5)));

  final resumen = <String, int>{};

  // ---------------------------------------------------------------------------
  // Estado en memoria
  // ---------------------------------------------------------------------------
  final _sedes = <_Sede>[];
  final _areas = <String, String>{};
  final _subAreas = <String, String>{};
  final _subAreaArea = <String, String>{};
  final _tipos = <String, String>{};
  final _programas = <String, _Prog>{};
  final _roles = <String, String>{};
  final _usuarios = <Map<String, Object?>>[];
  final _usuarioRoles = <Map<String, Object?>>[];
  final _coordinadores = <String>[];
  final _profs = <_Prof>[];
  final _reps = <_Rep>[];
  final _pacientes = <_Paciente>[];
  final _matriculas = <_Mat>[];
  final _contratos = <_Contrato>[];
  final _cohortes = <_Cohorte>[];
  final _sesiones = <_Sesion>[];
  final _feriados = <String>{};
  final _ocupProf = <String, Set<int>>{};
  final _ocupPac = <String, Set<int>>{};
  final _cedulas = <String>{};
  final _correos = <String>{};
  var _historia = 0;
  var _contratoNeuro = 5100;
  var _contratoIngles = 3200;
  var _grupo = 60;

  // ---------------------------------------------------------------------------
  // Orquestación
  // ---------------------------------------------------------------------------
  Future<Map<String, int>> ejecutar() async {
    await _db.execute("SET app.omitir_auditoria = 'on'");
    await _db.execute("SET TimeZone = 'America/Guayaquil'");
    final hash = await _db.execute(
      Sql.named("SELECT crypt(@p:text, gen_salt('bf', 8))"),
      parameters: {'p': passwordUsuarios},
    );
    final passwordHash = hash.first.first! as String;

    await _db.runTx((tx) async {
      final db = _Lotes(tx, llave, resumen);
      await _cargarRoles(tx);
      await _organizacion(db);
      await _catalogo(db);
      _personal(passwordHash);
      _terapeutas(passwordHash);
      _familias(passwordHash);
      _planificarMatriculas();
      _agendarGrupos();
      _agendarIndividuales();
      _agendarValoraciones();
      _registrarAsistencia();
      _armarContratos();

      await _insertarPersonas(db);
      await _insertarAgenda(db);
      await _cerrarEstados(db);
      await _clinico(db);
      await _desempeno(db, tx);
      await _demandaYSolicitudes(db);
      await _notificaciones(db);
      await _indicadores(tx);
    });
    return resumen;
  }

  Future<void> _cargarRoles(Session tx) async {
    for (final f in await tx.execute('SELECT codigo, id::text FROM seguridad.roles')) {
      _roles[f[0]! as String] = f[1]! as String;
    }
  }

  // ---------------------------------------------------------------------------
  // Organización y catálogo
  // ---------------------------------------------------------------------------
  Future<void> _organizacion(_Lotes db) async {
    await db.insertar('organizacion.paises', [
      {'id': 'EC', 'nombre': 'Ecuador'},
    ], {'id': 'char(2)', 'nombre': 'text'});
    await db.insertar('organizacion.provincias', [
      {'id': 17, 'pais_id': 'EC', 'nombre': 'Pichincha'},
    ], {'id': 'int', 'pais_id': 'char(2)', 'nombre': 'text'});
    await db.insertar('organizacion.cantones', [
      {'id': 1701, 'provincia_id': 17, 'nombre': 'Quito'},
    ], {'id': 'int', 'provincia_id': 'int', 'nombre': 'text'});
    await db.insertar('organizacion.parroquias', [
      {'id': 170150, 'canton_id': 1701, 'nombre': 'La Magdalena'},
      {'id': 170157, 'canton_id': 1701, 'nombre': 'Kennedy'},
      {'id': 170184, 'canton_id': 1701, 'nombre': 'Tumbaco'},
    ], {'id': 'int', 'canton_id': 'int', 'nombre': 'text'});

    final rucId = _id();
    await db.insertar('organizacion.rucs', [
      {'id': rucId, 'numero_ruc': '9900000000001', 'canton_id': 1701, 'descripcion': 'RUC ficticio de pruebas'},
    ], {'id': 'uuid', 'numero_ruc': 'text', 'canton_id': 'int', 'descripcion': 'text'});

    final sedes = [
      ('VILLAFLORA', 'Villaflora', 170150, 'Av. Maldonado S10-45 y Gatazo', true),
      ('NORTE', 'Quito Norte', 170157, 'Av. De la Prensa N52-110', false),
      ('TUMBACO', 'Tumbaco', 170184, 'Av. Interoceánica km 14', false),
    ];
    final filasSedes = <Map<String, Object?>>[];
    final filasSalas = <Map<String, Object?>>[];
    for (final (codigo, nombre, parroquia, direccion, piscina) in sedes) {
      final sede = _Sede(_id(), codigo);
      _sedes.add(sede);
      filasSedes.add({
        'id': sede.id, 'codigo': codigo, 'nombre': nombre, 'parroquia_id': parroquia,
        'ruc_id': rucId, 'direccion': direccion, 'telefono': '0900${_digitos(6)}',
      });
      final salas = [
        ('Consultorio 1', 1), ('Consultorio 2', 1), ('Consultorio 3', 1), ('Consultorio 4', 1),
        ('Sala grupal', 8), ('Aula virtual', 40), if (piscina) ('Piscina', 6),
      ];
      for (final (nombreSala, capacidad) in salas) {
        final id = _id();
        sede.salas[nombreSala] = id;
        filasSalas.add({'id': id, 'sede_id': sede.id, 'nombre': nombreSala, 'capacidad': capacidad});
      }
    }
    await db.insertar('organizacion.sedes', filasSedes, {
      'id': 'uuid', 'codigo': 'text', 'nombre': 'text', 'parroquia_id': 'int',
      'ruc_id': 'uuid', 'direccion': 'text', 'telefono': 'text',
    });
    await db.insertar('organizacion.salas', filasSalas,
        {'id': 'uuid', 'sede_id': 'uuid', 'nombre': 'text', 'capacidad': 'smallint'});

    // Feriados nacionales (fechas aproximadas) y el feriado local de Quito.
    final nacionales = {
      '2026-01-01': 'Año Nuevo', '2026-02-16': 'Carnaval', '2026-02-17': 'Carnaval',
      '2026-04-03': 'Viernes Santo', '2026-05-01': 'Día del Trabajo', '2026-05-25': 'Batalla de Pichincha',
      '2026-08-10': 'Primer Grito de Independencia', '2026-10-09': 'Independencia de Guayaquil',
      '2026-11-02': 'Día de Difuntos', '2026-11-03': 'Independencia de Cuenca', '2026-12-25': 'Navidad',
      '2027-01-01': 'Año Nuevo', '2027-02-08': 'Carnaval', '2027-02-09': 'Carnaval',
      '2027-03-26': 'Viernes Santo', '2027-05-01': 'Día del Trabajo',
    };
    final filas = [
      for (final e in nacionales.entries) {'fecha': e.key, 'nombre': e.value, 'sede_id': null},
      for (final s in _sedes) {'fecha': '2026-12-04', 'nombre': 'Fundación de Quito', 'sede_id': s.id},
    ];
    _feriados
      ..addAll(nacionales.keys)
      ..add('2026-12-04');
    await db.insertar('organizacion.feriados', filas, {'fecha': 'date', 'nombre': 'text', 'sede_id': 'uuid'});
  }

  Future<void> _catalogo(_Lotes db) async {
    _areas['NEURO'] = _id();
    _areas['INGLES_ESTIMULACION'] = _id();
    await db.insertar('catalogo.areas', [
      {'id': _areas['NEURO'], 'codigo': 'NEURO', 'nombre': 'Neuro / Tomatis'},
      {'id': _areas['INGLES_ESTIMULACION'], 'codigo': 'INGLES_ESTIMULACION', 'nombre': 'Inglés / Estimulación'},
    ], {'id': 'uuid', 'codigo': 'text', 'nombre': 'text'});

    const subs = {
      'VALORACION': ('NEURO', 'Valoración'),
      'TOMATIS': ('NEURO', 'Método Tomatis'),
      'TERAPIA_LENGUAJE': ('NEURO', 'Terapia de lenguaje'),
      'TERAPIA_OCUPACIONAL': ('NEURO', 'Terapia ocupacional'),
      'PSICOLOGIA': ('NEURO', 'Psicología infantil'),
      'ESTIMULACION_TEMPRANA': ('INGLES_ESTIMULACION', 'Estimulación temprana'),
      'ESTIMULACION_ACUATICA': ('INGLES_ESTIMULACION', 'Estimulación acuática'),
      'INGLES': ('INGLES_ESTIMULACION', 'Inglés'),
    };
    final filas = <Map<String, Object?>>[];
    subs.forEach((codigo, v) {
      final id = _id();
      _subAreas[codigo] = id;
      _subAreaArea[codigo] = v.$1;
      filas.add({'id': id, 'area_id': _areas[v.$1], 'codigo': codigo, 'nombre': v.$2});
    });
    await db.insertar('catalogo.sub_areas', filas, {'id': 'uuid', 'area_id': 'uuid', 'codigo': 'text', 'nombre': 'text'});

    const tipos = {
      'VALORACION': ('Valoración', 'UNICO', true),
      'SEMANAL': ('Semanal con días fijos', 'SEMANAL_FIJO', false),
      'INTENSIVO': ('Bloque intensivo', 'BLOQUE_INTENSIVO', false),
      'LIBRE': ('Sesiones sueltas', 'LIBRE', false),
    };
    final filasTipos = <Map<String, Object?>>[];
    tipos.forEach((codigo, v) {
      final id = _id();
      _tipos[codigo] = id;
      filasTipos.add({'id': id, 'codigo': codigo, 'nombre': v.$1, 'patron': v.$2, 'es_valoracion': v.$3});
    });
    await db.insertar('catalogo.tipos_programa', filasTipos,
        {'id': 'uuid', 'codigo': 'text', 'nombre': 'text', 'patron': 'text', 'es_valoracion': 'boolean'});

    // Programas DE EJEMPLO: reemplazar por la lista real del centro.
    final defs = [
      _ProgDef('VALORACION_INICIAL', 'Valoración inicial', 'NEURO', 'VALORACION', 'VALORACION', 4, null, null,
          'INDIVIDUAL', 'PRESENCIAL', 1, false, 0, 60, const []),
      _ProgDef('TERAPIAS_ESPECIFICAS', 'Terapias específicas', 'NEURO', 'SEMANAL', 'TOMATIS', 32, 4, 2,
          'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 1280, const [('F1', 12, null), ('F2', 10, null), ('F3 - Integraciones', 10, 'TERAPIA_OCUPACIONAL')]),
      _ProgDef('TERAPIA_LENGUAJE', 'Terapia de lenguaje', 'NEURO', 'SEMANAL', 'TERAPIA_LENGUAJE', 24, 4, 2,
          'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 720, const [('Fase 1', 12, null), ('Fase 2', 12, null)]),
      _ProgDef('TERAPIA_OCUPACIONAL_GRUPAL', 'Terapia ocupacional grupal', 'NEURO', 'SEMANAL', 'TERAPIA_OCUPACIONAL', 24, 3, 2,
          'GRUPAL', 'PRESENCIAL', 5, true, 1, 480, const []),
      _ProgDef('TOMATIS_INTENSIVO', 'Tomatis intensivo', 'NEURO', 'INTENSIVO', 'TOMATIS', 15, 1, 5,
          'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 900, const []),
      _ProgDef('PSICOLOGIA_INFANTIL', 'Psicología infantil', 'NEURO', 'SEMANAL', 'PSICOLOGIA', 10, 3, 1,
          'INDIVIDUAL', 'PRESENCIAL', 1, true, 1, 350, const []),
      _ProgDef('ESTIMULACION_TEMPRANA', 'Estimulación temprana grupal', 'INGLES_ESTIMULACION', 'SEMANAL', 'ESTIMULACION_TEMPRANA', 24, 3, 2,
          'GRUPAL', 'PRESENCIAL', 5, false, 1, 420, const []),
      _ProgDef('ESTIMULACION_ACUATICA', 'Estimulación acuática', 'INGLES_ESTIMULACION', 'SEMANAL', 'ESTIMULACION_ACUATICA', 16, 2, 2,
          'GRUPAL', 'PRESENCIAL', 5, false, 1, 320, const []),
      _ProgDef('INGLES_KIDS', 'Inglés kids presencial', 'INGLES_ESTIMULACION', 'SEMANAL', 'INGLES', 48, 6, 2,
          'GRUPAL', 'PRESENCIAL', 8, false, 1, 960, const []),
      _ProgDef('INGLES_ONLINE', 'Inglés online', 'INGLES_ESTIMULACION', 'SEMANAL', 'INGLES', 48, 6, 2,
          'GRUPAL', 'ONLINE', 30, false, 1, 540, const []),
    ];
    final filasProg = <Map<String, Object?>>[];
    final filasFases = <Map<String, Object?>>[];
    for (final d in defs) {
      final prog = _Prog(_id(), d);
      _programas[d.codigo] = prog;
      filasProg.add({
        'id': prog.id, 'area_id': _areas[d.area], 'tipo_programa_id': _tipos[d.tipo],
        'sub_area_requerida_id': _subAreas[d.sub], 'codigo': d.codigo, 'nombre': d.nombre,
        'total_sesiones': d.total, 'duracion_meses': d.meses, 'duracion_sesion_min': 60,
        'sesiones_por_semana': d.porSemana, 'modalidad': d.modalidad, 'modalidad_entrega': d.entrega,
        'cupo_maximo': d.cupo, 'requiere_valoracion': d.requiereValoracion,
        'sesiones_antes_evaluacion': d.antesEvaluacion, 'precio_referencial': d.precio,
        'reglas_extra': {'ejemplo': true},
      });
      var orden = 1;
      for (final (nombre, sesiones, sub) in d.fases) {
        final fase = _Fase(_id(), sesiones, sub);
        prog.fases.add(fase);
        filasFases.add({
          'id': fase.id, 'programa_id': prog.id, 'orden': orden++, 'nombre': nombre,
          'sesiones': sesiones, 'sub_area_id': sub == null ? null : _subAreas[sub],
        });
      }
    }
    await db.insertar('catalogo.programas', filasProg, {
      'id': 'uuid', 'area_id': 'uuid', 'tipo_programa_id': 'uuid', 'sub_area_requerida_id': 'uuid',
      'codigo': 'text', 'nombre': 'text', 'total_sesiones': 'smallint', 'duracion_meses': 'smallint',
      'duracion_sesion_min': 'smallint', 'sesiones_por_semana': 'smallint', 'modalidad': 'text',
      'modalidad_entrega': 'text', 'cupo_maximo': 'smallint', 'requiere_valoracion': 'boolean',
      'sesiones_antes_evaluacion': 'smallint', 'precio_referencial': 'numeric', 'reglas_extra': 'jsonb',
    });
    await db.insertar('catalogo.programa_fases', filasFases, {
      'id': 'uuid', 'programa_id': 'uuid', 'orden': 'smallint', 'nombre': 'text', 'sesiones': 'smallint', 'sub_area_id': 'uuid',
    });

    await db.insertar('clinico.plantillas_nota', [
      {'nombre': 'Nota general de sesión', 'campos': ['Objetivo trabajado', 'Actividades', 'Respuesta del paciente', 'Recomendaciones']},
      {'nombre': 'Sesión Tomatis', 'programa_id': _programas['TOMATIS_INTENSIVO']!.id,
       'campos': ['Fase de escucha', 'Tolerancia', 'Observaciones de la familia']},
    ], {'nombre': 'text', 'campos': 'jsonb', 'programa_id': 'uuid'});
  }

  // ---------------------------------------------------------------------------
  // Personas
  // ---------------------------------------------------------------------------
  String _nuevoUsuario(String nombres, String apellidos, String dominio, String hash, {String? prefijo}) {
    final id = _id();
    final base = prefijo ?? '${_slug(nombres.split(' ').first)}.${_slug(apellidos.split(' ').first)}';
    var correo = '$base@$dominio';
    var n = 2;
    while (!_correos.add(correo)) {
      correo = '$base$n@$dominio';
      n++;
    }
    _usuarios.add({
      'id': id, 'email': correo, 'password_hash': hash, 'nombres': nombres, 'apellidos': apellidos,
      'telefono': '0900${_digitos(6)}', 'mfa_activo': false,
    });
    return id;
  }

  void _asignarRol(String usuarioId, String rol, {String? sedeId, String? area}) {
    _usuarioRoles.add({
      'usuario_id': usuarioId, 'rol_id': _roles[rol], 'sede_id': sedeId,
      'area_id': area == null ? null : _areas[area], 'vigente_desde': _f(hoy.subtract(const Duration(days: 365))),
    });
  }

  void _personal(String hash) {
    final villaflora = _sedes[0].id;
    for (var i = 1; i <= 2; i++) {
      final u = _nuevoUsuario(_elegir(nombresAdultasF), _apellidos(), 'ismart.test', hash, prefijo: 'gerencia$i');
      _asignarRol(u, 'GERENCIA');
      final a = _nuevoUsuario(_elegir(nombresAdultosM), _apellidos(), 'ismart.test', hash, prefijo: 'admin$i');
      _asignarRol(a, 'ADMINISTRADOR');
    }
    // Coordinadores por área, como se definió en la reunión del 5/10/2026.
    final c1 = _nuevoUsuario(_elegir(nombresAdultasF), _apellidos(), 'ismart.test', hash, prefijo: 'coord.neuro.norte');
    _asignarRol(c1, 'COORDINADOR', sedeId: _sedes[1].id, area: 'NEURO');
    _asignarRol(c1, 'COORDINADOR', sedeId: _sedes[2].id, area: 'NEURO');
    final c2 = _nuevoUsuario(_elegir(nombresAdultosM), _apellidos(), 'ismart.test', hash, prefijo: 'coord.neuro.villaflora');
    _asignarRol(c2, 'COORDINADOR', sedeId: villaflora, area: 'NEURO');
    final c3 = _nuevoUsuario(_elegir(nombresAdultasF), _apellidos(), 'ismart.test', hash, prefijo: 'coord.ingles');
    _asignarRol(c3, 'COORDINADOR', area: 'INGLES_ESTIMULACION');
    final c4 = _nuevoUsuario(_elegir(nombresAdultasF), _apellidos(), 'ismart.test', hash, prefijo: 'coord.dos.areas');
    _asignarRol(c4, 'COORDINADOR', sedeId: villaflora);
    _coordinadores.addAll([c1, c2, c3, c4]);
    resumen['personal (gerencia, administración, coordinación)'] = 8;
  }

  void _terapeutas(String hash) {
    const plantilla = [
      ['VALORACION', 'PSICOLOGIA'], ['VALORACION', 'TERAPIA_LENGUAJE'], ['TOMATIS'], ['TOMATIS', 'TERAPIA_OCUPACIONAL'],
      ['TERAPIA_LENGUAJE'], ['TERAPIA_LENGUAJE'], ['TERAPIA_OCUPACIONAL'], ['TERAPIA_OCUPACIONAL'],
      ['PSICOLOGIA'], ['ESTIMULACION_TEMPRANA', 'ESTIMULACION_ACUATICA'], ['INGLES'], ['INGLES'],
    ];
    const profesiones = {
      'VALORACION': 'Psicóloga clínica', 'TOMATIS': 'Terapeuta Tomatis', 'TERAPIA_LENGUAJE': 'Terapeuta de lenguaje',
      'TERAPIA_OCUPACIONAL': 'Terapeuta ocupacional', 'PSICOLOGIA': 'Psicóloga infantil',
      'ESTIMULACION_TEMPRANA': 'Estimuladora temprana', 'INGLES': 'Docente de inglés',
    };
    const colores = ['#1D5F8A', '#2E7D5B', '#9A5B00', '#6B4FA3', '#B23A48', '#00796B', '#5D6D7E', '#C2185B'];
    var n = 0;
    for (final sede in _sedes) {
      for (final subs in plantilla) {
        final mujer = _r.nextDouble() < 0.75;
        final nombres = mujer ? _elegir(nombresAdultasF) : _elegir(nombresAdultosM);
        final apellidos = _apellidos();
        final usuario = _nuevoUsuario(nombres, apellidos, 'ismart.test', hash);
        final area = _subAreaArea[subs.first]!;
        _asignarRol(usuario, 'TERAPEUTA', sedeId: sede.id, area: area);
        final manana = n.isEven;
        final sabado = n % 3 == 0;
        final horas = <int, List<int>>{};
        for (var dia = 1; dia <= 5; dia++) {
          horas[dia] = manana ? [8, 9, 10, 11, 12, 14, 15, 16] : [10, 11, 12, 13, 15, 16, 17, 18];
        }
        horas[3]!.remove(16);
        horas[5]!.remove(18);
        if (sabado) horas[6] = [8, 9, 10, 11, 12];
        final prof = _Prof(
          id: _id(), usuarioId: usuario, sede: sede, subAreas: subs, nombres: nombres, apellidos: apellidos,
          profesion: profesiones[subs.first]!, color: colores[n % colores.length], manana: manana, horas: horas,
          calidad: 3.4 + _r.nextDouble() * 1.5,
        );
        _profs.add(prof);
        _ocupProf[prof.id] = {};
        n++;
      }
    }
    // Vacaciones de una semana y permisos de un día.
    for (final p in (_profs.toList()..shuffle(_r)).take(8)) {
      final lunes = _lunes(hoy.add(Duration(days: _entre(-100, 40))));
      p.ausencias.add((lunes, lunes.add(const Duration(days: 6)), 'VACACIONES'));
    }
    for (final p in (_profs.toList()..shuffle(_r)).take(6)) {
      final dia = _diaHabil(hoy.add(Duration(days: _entre(-60, 30))));
      p.ausencias.add((dia, dia.add(const Duration(days: 1)), _r.nextBool() ? 'PERMISO' : 'CAPACITACION'));
    }
    resumen['terapeutas'] = _profs.length;
  }

  void _familias(String hash) {
    const familias = 175;
    const pacientesTotal = 255;
    final listaFamilias = <List<_Rep>>[];
    for (var i = 0; i < familias; i++) {
      final apellidoPadre = _elegir(apellidos);
      final apellidoMadre = _elegir(apellidos);
      final sede = _elegirPeso(_sedes, const [40, 35, 25]);
      final direccion = '${_elegir(calles)} ${_entre(1, 80)}-${_entre(10, 99)}';
      final parentesco = _elegirPeso(const ['MADRE', 'PADRE', 'ABUELA', 'TUTOR'], const [70, 24, 4, 2]);
      final reps = <_Rep>[_crearRep(parentesco, apellidoPadre, apellidoMadre, direccion, hash, sede)];
      if (i < 30) {
        reps.add(_crearRep(parentesco == 'MADRE' ? 'PADRE' : 'MADRE', apellidoPadre, apellidoMadre, direccion, hash, sede));
      }
      listaFamilias.add(reps);
    }
    for (var i = 0; i < pacientesTotal; i++) {
      final familia = i < familias ? listaFamilias[i] : _elegir(listaFamilias);
      final principal = familia.first;
      final mujer = _r.nextBool();
      final paciente = _Paciente(
        id: _id(), historia: 'HC-${(++_historia).toString().padLeft(5, '0')}',
        nombres: '${mujer ? _elegir(nombresNinas) : _elegir(nombresNinos)}${_r.nextDouble() < 0.4 ? ' ${mujer ? _elegir(nombresNinas) : _elegir(nombresNinos)}' : ''}',
        apellidos: '${principal.apellidoPadre} ${principal.apellidoMadre}', sexo: mujer ? 'F' : 'M',
        sede: principal.sede, direccion: principal.direccion, cedula: _cedula(), reps: familia,
      );
      _pacientes.add(paciente);
      _ocupPac[paciente.id] = {};
    }
    resumen['representantes'] = _reps.length;
    resumen['pacientes'] = _pacientes.length;
  }

  _Rep _crearRep(String parentesco, String apPadre, String apMadre, String direccion, String hash, _Sede sede) {
    final mujer = parentesco == 'MADRE' || parentesco == 'ABUELA';
    final nombres = mujer ? _elegir(nombresAdultasF) : _elegir(nombresAdultosM);
    final apellidos = parentesco == 'PADRE' ? '$apPadre ${_elegir(apellidosLista)}' : '$apMadre ${_elegir(apellidosLista)}';
    final usuario = _nuevoUsuario(nombres, apellidos, 'ejemplo.test', hash);
    _asignarRol(usuario, 'REPRESENTANTE');
    final rep = _Rep(_id(), usuario, nombres, apellidos, parentesco, _cedula(), apPadre, apMadre, direccion, sede);
    _reps.add(rep);
    return rep;
  }

  // ---------------------------------------------------------------------------
  // Matrículas y agenda
  // ---------------------------------------------------------------------------
  static const _edades = {
    'TERAPIAS_ESPECIFICAS': (3, 10), 'TERAPIA_LENGUAJE': (3, 9), 'TERAPIA_OCUPACIONAL_GRUPAL': (4, 9),
    'TOMATIS_INTENSIVO': (4, 12), 'PSICOLOGIA_INFANTIL': (5, 13), 'ESTIMULACION_TEMPRANA': (1, 3),
    'ESTIMULACION_ACUATICA': (1, 5), 'INGLES_KIDS': (5, 12), 'INGLES_ONLINE': (7, 14),
  };
  static const _combinaciones = {
    'TERAPIA_LENGUAJE': 'TERAPIA_OCUPACIONAL_GRUPAL',
    'TERAPIAS_ESPECIFICAS': 'PSICOLOGIA_INFANTIL',
    'PSICOLOGIA_INFANTIL': 'TERAPIA_LENGUAJE',
    'ESTIMULACION_TEMPRANA': 'ESTIMULACION_ACUATICA',
    'TERAPIA_OCUPACIONAL_GRUPAL': 'INGLES_KIDS',
  };

  void _planificarMatriculas() {
    const pesos = {
      'TERAPIAS_ESPECIFICAS': 18, 'TERAPIA_LENGUAJE': 18, 'TERAPIA_OCUPACIONAL_GRUPAL': 12, 'TOMATIS_INTENSIVO': 6,
      'PSICOLOGIA_INFANTIL': 10, 'ESTIMULACION_TEMPRANA': 12, 'ESTIMULACION_ACUATICA': 8, 'INGLES_KIDS': 10, 'INGLES_ONLINE': 6,
    };
    for (final p in _pacientes) {
      final codigo = _elegirPeso(pesos.keys.toList(), pesos.values.toList());
      final (min, max) = _edades[codigo]!;
      final meses = _entre(min * 12, max * 12 + 11);
      p.nacimiento = DateTime.utc(hoy.year, hoy.month, hoy.day).subtract(Duration(days: (meses * 30.4).round() + _entre(0, 25)));
      if (_r.nextDouble() < 0.08) {
        p.prospecto = true;
        continue;
      }
      final inicio = _diaHabil(hoy.add(Duration(days: _entre(-170, 28))));
      _nuevaMatricula(p, _programas[codigo]!, inicio);
      final segundo = _combinaciones[codigo];
      if (segundo != null && _r.nextDouble() < 0.22) {
        _nuevaMatricula(p, _programas[segundo]!, _diaHabil(inicio.add(Duration(days: _entre(0, 20)))));
      }
    }
    // Retiros y congelamientos en algunas matrículas individuales.
    final individuales = _matriculas
        .where((m) => m.prog.def.modalidad == 'INDIVIDUAL' && m.inicio.isBefore(hoy.subtract(const Duration(days: 45))))
        .toList()
      ..shuffle(_r);
    for (final m in individuales.take(5)) {
      m.retiroDesde = m.inicio.add(Duration(days: _entre(20, 35)));
    }
    for (final m in individuales.skip(5).take(6)) {
      final desde = m.inicio.add(Duration(days: _entre(18, 30)));
      m.congelamiento = (desde, desde.add(const Duration(days: 13)));
    }
    final enCurso = _matriculas.where((m) => m.prog.def.modalidad == 'INDIVIDUAL' && m.inicio.isAfter(hoy.subtract(const Duration(days: 30))) && m.inicio.isBefore(hoy)).toList();
    for (final m in enCurso.take(2)) {
      final desde = hoy.subtract(const Duration(days: 3));
      m.congelamiento = (desde, desde.add(const Duration(days: 14)));
    }
  }

  void _nuevaMatricula(_Paciente p, _Prog prog, DateTime inicio) {
    final m = _Mat(_id(), p, prog, inicio);
    p.matriculas.add(m);
    _matriculas.add(m);
    if (prog.def.modalidad != 'INDIVIDUAL') {
      final cohorte = _cohortePara(m);
      m.cohorte = cohorte;
      m.inicio = cohorte.inicio;
      cohorte.miembros.add(m);
    }
  }

  _Cohorte _cohortePara(_Mat m) {
    final prog = m.prog;
    final online = prog.def.entrega == 'ONLINE';
    final sede = online ? _sedes[0] : m.paciente.sede;
    final patronesPaciente = m.paciente.matriculas.where((x) => x.cohorte != null).expand((x) => x.cohorte!.patron).toSet();
    for (final c in _cohortes) {
      if (c.prog == prog && c.sede == sede && c.miembros.length < c.objetivo &&
          (c.inicio.difference(m.inicio).inDays).abs() < 75 && !c.patron.any(patronesPaciente.contains)) {
        return c;
      }
    }
    final candidatos = _profs.where((p) => p.sede == sede && p.subAreas.contains(prog.def.sub)).toList();
    final prof = candidatos[_r.nextInt(candidatos.length)];
    final inicio = _lunes(m.inicio);
    List<Franja> patron;
    var intentos = 0;
    do {
      const pares = [(1, 3), (2, 4), (3, 5), (1, 4), (2, 5)];
      final (d1, d2) = pares[_r.nextInt(pares.length)];
      final comunes = prof.horas[d1]!.where(prof.horas[d2]!.contains).toList();
      final hora = comunes[_r.nextInt(comunes.length)];
      patron = [(d1, hora), (d2, hora)];
      intentos++;
    } while (intentos < 20 && (patron.any(patronesPaciente.contains) ||
        _cohortes.any((c) => c.prof == prof && c.patron.any(patron.contains))));
    final salaNombre = online ? 'Aula virtual' : prog.def.sub == 'ESTIMULACION_ACUATICA' && sede.salas.containsKey('Piscina') ? 'Piscina' : 'Sala grupal';
    final cohorte = _Cohorte(
      id: _id(), codigo: 'G-${_grupo++}', prog: prog, sede: sede, prof: prof, salaId: sede.salas[salaNombre]!,
      cupo: prog.def.cupo, objetivo: online ? _entre(8, 20) : _entre(3, prog.def.cupo),
      inicio: inicio, patron: patron,
    );
    _cohortes.add(cohorte);
    return cohorte;
  }

  void _agendarGrupos() {
    for (final c in _cohortes) {
      final fechas = _generarFechas(
        desde: c.inicio, patron: c.patron, cantidad: c.prog.def.total,
        disponible: (t) => _profLibre(c.prof, t) && c.miembros.every((m) => _pacLibre(m.paciente, t)),
      );
      for (final t in fechas) {
        final sesion = _Sesion(_id(), c.sede, c.prof, c.prog, 'PROGRAMA', t, c.cupo)
          ..grupo = c
          ..salaId = c.salaId
          ..entrega = c.prog.def.entrega;
        _ocupar(c.prof, t);
        for (final m in c.miembros) {
          _ocuparPac(m.paciente, t);
          final part = _Part(_id(), sesion, m.paciente, m, m.sesiones.length + 1);
          m.sesiones.add(part);
          sesion.participantes.add(part);
        }
        _sesiones.add(sesion);
      }
    }
  }

  void _agendarIndividuales() {
    final individuales = _matriculas.where((m) => m.cohorte == null).toList()..sort((a, b) => a.inicio.compareTo(b.inicio));
    for (final m in individuales) {
      final def = m.prog.def;
      final tramos = m.prog.fases.isEmpty ? [_Fase('', def.total, null)] : m.prog.fases;
      var desde = m.inicio;
      for (final fase in tramos) {
        final sub = fase.sub ?? def.sub;
        final prof = _profMenosCargado(m.paciente.sede, sub, desde);
        final patron = _elegirPatron(prof, m.paciente, desde, def.porSemana ?? 1);
        m.patron ??= patron;
        final bloqueadas = <String>{};
        final congel = m.congelamiento;
        if (congel != null) {
          for (var d = congel.$1; !d.isAfter(congel.$2); d = d.add(const Duration(days: 1))) {
            bloqueadas.add(_f(d));
          }
        }
        final fechas = _generarFechas(
          desde: desde, patron: patron, cantidad: fase.sesiones, bloqueadas: bloqueadas,
          disponible: (t) => _profLibre(prof, t) && _pacLibre(m.paciente, t),
        );
        for (final t in fechas) {
          final sesion = _Sesion(_id(), m.paciente.sede, prof, m.prog, 'PROGRAMA', t, 1)
            ..salaId = m.paciente.sede.salas['Consultorio ${_entre(1, 4)}']
            ..plan = m;
          _ocupar(prof, t);
          _ocuparPac(m.paciente, t);
          final part = _Part(_id(), sesion, m.paciente, m, m.sesiones.length + 1)..faseId = fase.id.isEmpty ? null : fase.id;
          m.sesiones.add(part);
          sesion.participantes.add(part);
          _sesiones.add(sesion);
        }
        if (fechas.isNotEmpty) desde = fechas.last.add(const Duration(days: 1));
      }
    }
  }

  void _agendarValoraciones() {
    final valoracion = _programas['VALORACION_INICIAL']!;
    for (final p in _pacientes) {
      final primera = p.matriculas.isEmpty ? null : (p.matriculas.toList()..sort((a, b) => a.inicio.compareTo(b.inicio))).first;
      if (!p.prospecto && (primera == null || !primera.prog.def.requiereValoracion)) continue;
      final cantidad = p.prospecto ? _entre(1, 2) : _entre(1, 3);
      final (desde, hasta) = p.prospecto
          ? (hoy.subtract(const Duration(days: 30)), hoy.add(const Duration(days: 14)))
          : (primera!.inicio.subtract(const Duration(days: 21)), primera.inicio.subtract(const Duration(days: 2)));
      final evaluadores = _profs.where((x) => x.sede == p.sede && x.subAreas.contains('VALORACION')).toList();
      var hechas = 0;
      for (var intento = 0; intento < 60 && hechas < cantidad; intento++) {
        final dia = desde.add(Duration(days: _r.nextInt(max(1, hasta.difference(desde).inDays))));
        final prof = evaluadores[_r.nextInt(evaluadores.length)];
        final horas = prof.horas[dia.weekday];
        if (horas == null) continue;
        final t = DateTime.utc(dia.year, dia.month, dia.day, horas[_r.nextInt(horas.length)]);
        if (!_profLibre(prof, t) || !_pacLibre(p, t)) continue;
        final sesion = _Sesion(_id(), p.sede, prof, valoracion, 'VALORACION', t, 1)..salaId = p.sede.salas['Consultorio 1'];
        _ocupar(prof, t);
        _ocuparPac(p, t);
        sesion.participantes.add(_Part(_id(), sesion, p, null, ++hechas));
        _sesiones.add(sesion);
      }
    }
  }

  void _registrarAsistencia() {
    for (final s in _sesiones) {
      final pasada = s.inicio.isBefore(hoy);
      final retiro = s.participantes.length == 1 ? s.participantes.first.mat?.retiroDesde : null;
      if (retiro != null && !s.inicio.isBefore(retiro)) {
        s.estado = 'CANCELADA';
        s.motivo = 'Paciente retirado del programa';
        s.participantes.first.asistencia = 'CANCELADA';
        continue;
      }
      if (!pasada) continue;
      s.estado = 'REALIZADA';
      for (final part in s.participantes) {
        final x = _r.nextDouble();
        if (s.tipo == 'VALORACION') {
          part.asistencia = x < 0.92 ? 'ASISTIO' : 'FALTA';
        } else {
          part.asistencia = x < 0.86 ? 'ASISTIO' : x < 0.92 ? 'FALTA' : x < 0.97 ? 'FALTA_JUSTIFICADA' : 'CANCELADA';
        }
      }
      if (s.participantes.length == 1 && s.participantes.first.asistencia == 'CANCELADA') {
        s.estado = 'CANCELADA';
        s.motivo = 'La familia canceló con anticipación';
      }
    }
  }

  void _armarContratos() {
    for (final p in _pacientes.where((p) => p.matriculas.isNotEmpty)) {
      final mats = p.matriculas.toList()..sort((a, b) => a.inicio.compareTo(b.inicio));
      final neuro = mats.first.prog.def.area == 'NEURO';
      final codigo = neuro ? 'NESC-${_contratoNeuro++}' : 'IGE-${_contratoIngles++}';
      final desde = mats.first.inicio;
      var hasta = desde;
      for (final m in mats) {
        final ultima = m.sesiones.isEmpty ? m.inicio : m.sesiones.last.sesion.inicio;
        final porMeses = DateTime.utc(m.inicio.year, m.inicio.month + (m.prog.def.meses ?? 1) + 1, m.inicio.day);
        final fin = ultima.isAfter(porMeses) ? ultima.add(const Duration(days: 15)) : porMeses;
        m.finEstimado = _soloFecha(ultima);
        if (fin.isAfter(hasta)) hasta = fin;
      }
      final total = mats.fold<double>(0, (s, m) => s + m.prog.def.precio);
      final plan = _r.nextDouble() < 0.65;
      final contrato = _Contrato(
        _id(), codigo, p.reps.first, p.sede, plan ? 'PLAN' : 'CONTADO',
        plan ? total : (total * 0.92).roundToDouble(), desde.subtract(Duration(days: _entre(0, 10))), desde, _soloFecha(hasta), mats,
      );
      for (final m in mats) {
        m.contrato = contrato;
      }
      _contratos.add(contrato);
    }
  }

  // ---------------------------------------------------------------------------
  // Inserción
  // ---------------------------------------------------------------------------
  Future<void> _insertarPersonas(_Lotes db) async {
    await db.insertar('seguridad.usuarios', _usuarios, {
      'id': 'uuid', 'email': 'text', 'password_hash': 'text', 'nombres': 'text', 'apellidos': 'text',
      'telefono': 'text', 'mfa_activo': 'boolean',
    });
    await db.insertar('seguridad.usuario_roles', _usuarioRoles,
        {'usuario_id': 'uuid', 'rol_id': 'uuid', 'sede_id': 'uuid', 'area_id': 'uuid', 'vigente_desde': 'date'});

    await db.insertar('personas.profesionales', [
      for (final p in _profs)
        {
          'id': p.id, 'usuario_id': p.usuarioId, 'cedula': _cedula(), 'nombres': p.nombres, 'apellidos': p.apellidos,
          'profesion': p.profesion, 'color_agenda': p.color, 'fecha_ingreso': _f(hoy.subtract(Duration(days: _entre(120, 2000)))),
        },
    ], {
      'id': 'uuid', 'usuario_id': 'uuid', 'cedula': 'text', 'nombres': 'text', 'apellidos': 'text',
      'profesion': 'text', 'color_agenda': 'text', 'fecha_ingreso': 'date',
    });
    await db.insertar('personas.profesional_sub_areas', [
      for (final p in _profs)
        for (final (i, s) in p.subAreas.indexed) {'profesional_id': p.id, 'sub_area_id': _subAreas[s], 'es_principal': i == 0},
    ], {'profesional_id': 'uuid', 'sub_area_id': 'uuid', 'es_principal': 'boolean'});

    await db.insertar('personas.representantes', [
      for (final r in _reps)
        {
          'id': r.id, 'usuario_id': r.usuarioId, 'cedula': r.cedula, 'nombres': r.nombres, 'apellidos': r.apellidos,
          'telefono': '0900${_digitos(6)}', 'email': _usuarios.firstWhere((u) => u['id'] == r.usuarioId)['email'],
          'direccion': r.direccion,
        },
    ], {
      'id': 'uuid', 'usuario_id': 'uuid', 'cedula': 'text', 'nombres': 'text', 'apellidos': 'text',
      'telefono': 'text', 'email': 'text', 'direccion': 'text',
    });

    await db.insertar('personas.pacientes', [
      for (final p in _pacientes)
        {
          'id': p.id, 'codigo_historia': p.historia, 'cedula': p.cedula, 'nombres': p.nombres, 'apellidos': p.apellidos,
          'fecha_nacimiento': _f(p.nacimiento), 'sexo': p.sexo, 'direccion': p.direccion,
          'sede_principal_id': p.sede.id, 'estado': p.prospecto ? 'PROSPECTO' : 'ACTIVO',
        },
    ], {
      'id': 'uuid', 'codigo_historia': 'text', 'cedula': 'text', 'nombres': 'text', 'apellidos': 'text',
      'fecha_nacimiento': 'date', 'sexo': 'text', 'direccion': 'text', 'sede_principal_id': 'uuid', 'estado': 'text',
    }, expresiones: {
      'cedula': 'comun.cifrar(x."cedula", @llave:text)',
      'cedula_huella': 'comun.huella(x."cedula", @llave:text)',
    });

    await db.insertar('personas.paciente_representantes', [
      for (final p in _pacientes)
        for (final (i, r) in p.reps.indexed)
          {'paciente_id': p.id, 'representante_id': r.id, 'parentesco': r.parentesco, 'es_principal': i == 0},
    ], {'paciente_id': 'uuid', 'representante_id': 'uuid', 'parentesco': 'text', 'es_principal': 'boolean'});

    await db.insertar('matriculas.contratos', [
      for (final c in _contratos)
        {
          'id': c.id, 'codigo': c.codigo, 'representante_id': c.rep.id, 'sede_id': c.sede.id, 'tipo': c.tipo,
          'valor_total': c.valor, 'fecha_firma': _f(c.firma), 'vigente_desde': _f(c.desde), 'vigente_hasta': _f(c.hasta),
        },
    ], {
      'id': 'uuid', 'codigo': 'text', 'representante_id': 'uuid', 'sede_id': 'uuid', 'tipo': 'text',
      'valor_total': 'numeric', 'fecha_firma': 'date', 'vigente_desde': 'date', 'vigente_hasta': 'date',
    });
    resumen['contratos'] = _contratos.length;

    await db.insertar('matriculas.matriculas', [
      for (final m in _matriculas)
        {
          'id': m.id, 'contrato_id': m.contrato!.id, 'paciente_id': m.paciente.id, 'programa_id': m.prog.id,
          'fase_actual_id': m.prog.fases.isEmpty ? null : m.prog.fases.first.id,
          'jornada_preferida': (m.sesiones.isNotEmpty && m.sesiones.first.sesion.inicio.hour < 13) ? 'MANANA' : 'TARDE',
          'fecha_inicio': _f(m.inicio), 'fecha_fin_estimada': _f(m.finEstimado ?? m.inicio),
          'sesiones_contratadas': m.prog.def.total,
        },
    ], {
      'id': 'uuid', 'contrato_id': 'uuid', 'paciente_id': 'uuid', 'programa_id': 'uuid', 'fase_actual_id': 'uuid',
      'jornada_preferida': 'text', 'fecha_inicio': 'date', 'fecha_fin_estimada': 'date', 'sesiones_contratadas': 'smallint',
    });
    resumen['matrículas'] = _matriculas.length;

    await db.insertar('matriculas.congelamientos', [
      for (final m in _matriculas.where((m) => m.congelamiento != null))
        {'matricula_id': m.id, 'desde': _f(m.congelamiento!.$1), 'hasta': _f(m.congelamiento!.$2), 'motivo': 'Viaje familiar'},
    ], {'matricula_id': 'uuid', 'desde': 'date', 'hasta': 'date', 'motivo': 'text'});
  }

  Future<void> _insertarAgenda(_Lotes db) async {
    final jornadas = <Map<String, Object?>>[];
    final pausas = <Map<String, Object?>>[];
    final desde = _f(DateTime.utc(hoy.year - 1, 1, 1));
    for (final p in _profs) {
      for (final dia in p.horas.keys) {
        final sabado = dia == 6;
        jornadas.add({
          'profesional_id': p.id, 'sede_id': p.sede.id, 'dia_semana': dia, 'vigente_desde': desde,
          'hora_inicio': sabado ? '08:00' : p.manana ? '08:00' : '10:00',
          'hora_fin': sabado ? '13:00' : p.manana ? '17:00' : '19:00',
        });
        if (!sabado) {
          pausas.add({
            'profesional_id': p.id, 'dia_semana': dia, 'tipo': 'ALMUERZO', 'vigente_desde': desde,
            'hora_inicio': p.manana ? '13:00' : '14:00', 'hora_fin': p.manana ? '14:00' : '15:00',
          });
        }
      }
      pausas.add({
        'profesional_id': p.id, 'dia_semana': p.manana ? 3 : 5, 'tipo': 'ADMINISTRATIVA', 'vigente_desde': desde,
        'hora_inicio': p.manana ? '16:00' : '18:00', 'hora_fin': p.manana ? '17:00' : '19:00',
      });
    }
    await db.insertar('agenda.jornadas', jornadas, {
      'profesional_id': 'uuid', 'sede_id': 'uuid', 'dia_semana': 'smallint', 'vigente_desde': 'date',
      'hora_inicio': 'time', 'hora_fin': 'time',
    });
    await db.insertar('agenda.pausas', pausas, {
      'profesional_id': 'uuid', 'dia_semana': 'smallint', 'tipo': 'text', 'vigente_desde': 'date',
      'hora_inicio': 'time', 'hora_fin': 'time',
    });
    await db.insertar('agenda.ausencias', [
      for (final p in _profs)
        for (final (ini, fin, tipo) in p.ausencias)
          {
            'profesional_id': p.id, 'inicio': _ts(ini), 'fin': _ts(fin), 'tipo': tipo,
            'motivo': tipo == 'VACACIONES' ? 'Vacaciones programadas' : null, 'aprobado_por': _coordinadores.first,
          },
    ], {'profesional_id': 'uuid', 'inicio': 'timestamptz', 'fin': 'timestamptz', 'tipo': 'text', 'motivo': 'text', 'aprobado_por': 'uuid'});

    await db.insertar('agenda.grupos', [
      for (final c in _cohortes)
        {
          'id': c.id, 'codigo': c.codigo, 'programa_id': c.prog.id, 'sede_id': c.sede.id, 'profesional_id': c.prof.id,
          'sala_id': c.salaId, 'cupo_maximo': c.cupo,
          'activo': c.miembros.any((m) => m.sesiones.any((s) => !s.sesion.inicio.isBefore(hoy))),
        },
    ], {
      'id': 'uuid', 'codigo': 'text', 'programa_id': 'uuid', 'sede_id': 'uuid', 'profesional_id': 'uuid',
      'sala_id': 'uuid', 'cupo_maximo': 'smallint', 'activo': 'boolean',
    });
    resumen['grupos'] = _cohortes.length;
    await db.insertar('agenda.grupo_miembros', [
      for (final c in _cohortes)
        for (final m in c.miembros) {'grupo_id': c.id, 'matricula_id': m.id, 'desde': _f(c.inicio), 'hasta': _f(m.finEstimado ?? c.inicio)},
    ], {'grupo_id': 'uuid', 'matricula_id': 'uuid', 'desde': 'date', 'hasta': 'date'});

    final planes = <Map<String, Object?>>[];
    for (final m in _matriculas) {
      final patron = m.cohorte?.patron ?? m.patron ?? const [];
      final profId = m.cohorte?.prof.id ?? (m.sesiones.isEmpty ? null : m.sesiones.first.sesion.prof.id);
      m.planId = _id();
      planes.add({
        'id': m.planId, 'matricula_id': m.id, 'grupo_id': m.cohorte?.id, 'fecha_inicio': _f(m.inicio),
        'patron': [for (final (dia, hora) in patron) {'dia': dia, 'hora': '${_2(hora)}:00', 'profesional_id': profId}],
        'sesiones_a_generar': m.prog.def.total,
        'estado': m.sesiones.every((s) => s.sesion.inicio.isBefore(hoy)) ? 'FINALIZADO' : 'ACTIVO',
      });
    }
    await db.insertar('agenda.planes_agenda', planes, {
      'id': 'uuid', 'matricula_id': 'uuid', 'grupo_id': 'uuid', 'fecha_inicio': 'date', 'patron': 'jsonb',
      'sesiones_a_generar': 'smallint', 'estado': 'text',
    });

    _sesiones.sort((a, b) => a.inicio.compareTo(b.inicio));
    await db.insertar('agenda.sesiones', [
      for (final s in _sesiones)
        {
          'id': s.id, 'sede_id': s.sede.id, 'sala_id': s.salaId, 'profesional_id': s.prof.id, 'programa_id': s.prog?.id,
          'grupo_id': s.grupo?.id, 'plan_id': s.plan?.planId, 'tipo': s.tipo, 'modalidad_entrega': s.entrega,
          'inicio': _ts(s.inicio), 'fin': _ts(s.inicio.add(const Duration(hours: 1))), 'cupo_maximo': s.cupo,
          'estado': s.estado, 'motivo_cancelacion': s.motivo,
        },
    ], {
      'id': 'uuid', 'sede_id': 'uuid', 'sala_id': 'uuid', 'profesional_id': 'uuid', 'programa_id': 'uuid',
      'grupo_id': 'uuid', 'plan_id': 'uuid', 'tipo': 'text', 'modalidad_entrega': 'text', 'inicio': 'timestamptz',
      'fin': 'timestamptz', 'cupo_maximo': 'smallint', 'estado': 'text', 'motivo_cancelacion': 'text',
    });
    resumen['sesiones'] = _sesiones.length;

    final participantes = <Map<String, Object?>>[];
    for (final s in _sesiones) {
      for (final p in s.participantes) {
        final marcada = p.asistencia != 'PENDIENTE' && p.asistencia != 'CANCELADA';
        participantes.add({
          'id': p.id, 'sesion_id': s.id, 'paciente_id': p.paciente.id, 'matricula_id': p.mat?.id,
          'numero_sesion': p.numero, 'fase_id': p.faseId ?? _faseDe(p), 'asistencia': p.asistencia,
          'marcado_por': marcada ? s.prof.usuarioId : null,
          'marcado_en': marcada ? _ts(s.inicio.add(const Duration(minutes: 65))) : null,
        });
      }
    }
    await db.insertar('agenda.participantes', participantes, {
      'id': 'uuid', 'sesion_id': 'uuid', 'paciente_id': 'uuid', 'matricula_id': 'uuid', 'numero_sesion': 'smallint',
      'fase_id': 'uuid', 'asistencia': 'text', 'marcado_por': 'uuid', 'marcado_en': 'timestamptz',
    });
    resumen['participaciones en sesiones'] = participantes.length;
  }

  String? _faseDe(_Part p) {
    final m = p.mat;
    if (m == null || m.prog.fases.isEmpty) return null;
    var acumulado = 0;
    for (final f in m.prog.fases) {
      acumulado += f.sesiones;
      if (p.numero <= acumulado) return f.id;
    }
    return m.prog.fases.last.id;
  }

  /// Fija el estado final de matrículas, contratos y pacientes según lo ocurrido.
  Future<void> _cerrarEstados(_Lotes db) async {
    final estadosMat = <Map<String, Object?>>[];
    for (final m in _matriculas) {
      final consumidas = m.sesiones.where((s) => s.asistencia == 'ASISTIO' || s.asistencia == 'FALTA').length;
      final pendientes = m.sesiones.where((s) => s.asistencia == 'PENDIENTE').length;
      final congel = m.congelamiento;
      String estado;
      if (m.retiroDesde != null) {
        estado = 'CANCELADA';
      } else if (congel != null && !hoy.isBefore(congel.$1) && !hoy.isAfter(congel.$2)) {
        estado = 'CONGELADA';
      } else if (pendientes == 0 && consumidas >= m.prog.def.total) {
        estado = 'COMPLETADA';
      } else if (pendientes == 0 && m.contrato!.hasta.isBefore(hoy)) {
        estado = 'VENCIDA';
      } else {
        estado = 'EN_CURSO';
      }
      m.estado = estado;
      String? fase;
      if (m.prog.fases.isNotEmpty) {
        var acumulado = 0;
        for (final f in m.prog.fases) {
          fase = f.id;
          acumulado += f.sesiones;
          if (consumidas < acumulado) break;
        }
      }
      estadosMat.add({'id': m.id, 'estado': estado, 'fase_actual_id': fase});
    }
    await db.actualizar('matriculas.matriculas', estadosMat, {'estado': 'text', 'fase_actual_id': 'uuid'});

    final estadosContrato = <Map<String, Object?>>[];
    for (final c in _contratos) {
      final estados = c.matriculas.map((m) => m.estado).toSet();
      final estado = estados.every((e) => e == 'CANCELADA')
          ? 'ANULADO'
          : estados.every((e) => e == 'COMPLETADA' || e == 'CANCELADA')
              ? 'FINALIZADO'
              : estados.contains('EN_CURSO') || estados.contains('CONGELADA')
                  ? (estados.every((e) => e == 'CONGELADA') ? 'CONGELADO' : 'VIGENTE')
                  : 'VENCIDO';
      estadosContrato.add({'id': c.id, 'estado': estado});
    }
    await db.actualizar('matriculas.contratos', estadosContrato, {'estado': 'text'});

    final estadosPac = <Map<String, Object?>>[];
    for (final p in _pacientes.where((p) => !p.prospecto)) {
      final estados = p.matriculas.map((m) => m.estado).toSet();
      final estado = estados.contains('EN_CURSO')
          ? 'ACTIVO'
          : estados.contains('CONGELADA')
              ? 'CONGELADO'
              : estados.every((e) => e == 'CANCELADA')
                  ? 'RETIRADO'
                  : 'GRADUADO';
      p.estado = estado;
      estadosPac.add({'id': p.id, 'estado': estado});
    }
    await db.actualizar('personas.pacientes', estadosPac, {'estado': 'text'});
  }

  // ---------------------------------------------------------------------------
  // Clínico
  // ---------------------------------------------------------------------------
  Future<void> _clinico(_Lotes db) async {
    const instrumentos = ['Perfil sensorial', 'Test de articulación', 'Escala de desarrollo', 'Entrevista clínica', 'Batería neuropsicológica'];
    final valoraciones = <Map<String, Object?>>[];
    for (final s in _sesiones.where((s) => s.tipo == 'VALORACION')) {
      final part = s.participantes.first;
      if (part.asistencia != 'ASISTIO') continue;
      final recomendado = part.paciente.matriculas.isNotEmpty
          ? part.paciente.matriculas.first.prog.id
          : _elegir(_programas.values.where((p) => p.def.codigo != 'VALORACION_INICIAL').toList()).id;
      valoraciones.add({
        'participante_id': part.id, 'profesional_id': s.prof.id, 'instrumento': _elegir(instrumentos),
        'resultados': 'Puntajes por área: atención ${_entre(40, 95)}, lenguaje ${_entre(40, 95)}, motricidad ${_entre(40, 95)}.',
        'conclusion': 'Se recomienda iniciar el programa sugerido y revaluar al finalizar.',
        'programa_recomendado_id': recomendado, 'creado_en': _ts(s.inicio.add(const Duration(hours: 2))),
      });
    }
    await db.insertar('clinico.valoraciones', valoraciones, {
      'participante_id': 'uuid', 'profesional_id': 'uuid', 'instrumento': 'text', 'resultados': 'text',
      'conclusion': 'text', 'programa_recomendado_id': 'uuid', 'creado_en': 'timestamptz',
    }, expresiones: {'resultados': 'comun.cifrar(x."resultados", @llave:text)'});
    resumen['valoraciones con resultado'] = valoraciones.length;

    final objetivos = <Map<String, Object?>>[];
    final objetivosPorMat = <String, List<String>>{};
    for (final m in _matriculas) {
      final cantidad = _entre(2, 3);
      final textos = (objetivosTerapeuticos.toList()..shuffle(_r)).take(cantidad);
      for (final t in textos) {
        final id = _id();
        objetivosPorMat.putIfAbsent(m.id, () => []).add(id);
        final logrado = m.estado == 'COMPLETADA' ? _r.nextDouble() < 0.8 : _r.nextDouble() < 0.2 && m.inicio.isBefore(hoy.subtract(const Duration(days: 40)));
        final fechaLogro = logrado ? (m.finEstimado ?? hoy).isAfter(hoy) ? hoy : (m.finEstimado ?? hoy) : null;
        objetivos.add({
          'id': id, 'matricula_id': m.id, 'descripcion': t, 'fecha_inicio': _f(m.inicio),
          'estado': logrado ? 'LOGRADO' : m.estado == 'CANCELADA' ? 'SUSPENDIDO' : 'EN_PROCESO',
          'fecha_logro': fechaLogro == null ? null : _f(fechaLogro),
        });
      }
    }
    await db.insertar('clinico.objetivos', objetivos,
        {'id': 'uuid', 'matricula_id': 'uuid', 'descripcion': 'text', 'fecha_inicio': 'date', 'estado': 'text', 'fecha_logro': 'date'});

    final notas = <Map<String, Object?>>[];
    final avances = <Map<String, Object?>>[];
    for (final s in _sesiones.where((s) => s.tipo == 'PROGRAMA' && s.estado == 'REALIZADA')) {
      for (final part in s.participantes.where((p) => p.asistencia == 'ASISTIO')) {
        if (_r.nextDouble() > 0.7) continue;
        final id = _id();
        final reciente = hoy.difference(s.inicio).inDays < 3;
        notas.add({
          'id': id, 'participante_id': part.id, 'profesional_id': s.prof.id, 'contenido': _elegir(notasClinicas),
          'resumen_familia': _elegir(resumenesFamilia),
          'firmada_en': reciente && _r.nextBool() ? null : _ts(s.inicio.add(const Duration(hours: 3))),
          'creado_en': _ts(s.inicio.add(const Duration(hours: 1))),
        });
        final objs = objetivosPorMat[part.mat!.id];
        if (objs != null && _r.nextDouble() < 0.35) {
          final nivel = (1 + 4 * part.numero / part.mat!.prog.def.total).round().clamp(1, 5);
          avances.add({
            'objetivo_id': _elegir(objs), 'nota_id': id, 'nivel': nivel,
            'comentario': nivel >= 4 ? 'Muy cerca de lograrlo' : 'Avance progresivo',
            'registrado_en': _ts(s.inicio.add(const Duration(hours: 1))),
          });
        }
      }
    }
    await db.insertar('clinico.notas_sesion', notas, {
      'id': 'uuid', 'participante_id': 'uuid', 'profesional_id': 'uuid', 'contenido': 'text',
      'resumen_familia': 'text', 'firmada_en': 'timestamptz', 'creado_en': 'timestamptz',
    }, expresiones: {'contenido': 'comun.cifrar(x."contenido", @llave:text)'});
    await db.insertar('clinico.avances_objetivo', avances,
        {'objetivo_id': 'uuid', 'nota_id': 'uuid', 'nivel': 'smallint', 'comentario': 'text', 'registrado_en': 'timestamptz'});
    resumen['notas de sesión'] = notas.length;

    final tareas = <Map<String, Object?>>[];
    for (final m in _matriculas.where((m) => m.estado == 'EN_CURSO')) {
      if (_r.nextDouble() > 0.4) continue;
      final prof = m.sesiones.isEmpty ? null : m.sesiones.first.sesion.prof;
      if (prof == null) continue;
      for (var i = 0; i < _entre(1, 3); i++) {
        final (titulo, descripcion) = _elegir(tareasCasa);
        final asignada = hoy.subtract(Duration(days: _entre(1, 30)));
        final hecha = _r.nextDouble() < 0.6;
        tareas.add({
          'paciente_id': m.paciente.id, 'profesional_id': prof.id, 'titulo': titulo, 'descripcion': descripcion,
          'fecha_asignada': _f(asignada), 'fecha_limite': _f(asignada.add(const Duration(days: 7))),
          'completada_en': hecha ? _ts(asignada.add(Duration(days: _entre(1, 6), hours: 19))) : null,
          'comentario_familia': hecha && _r.nextBool() ? 'Lo hicimos todos los días.' : null,
        });
      }
    }
    await db.insertar('clinico.tareas_casa', tareas, {
      'paciente_id': 'uuid', 'profesional_id': 'uuid', 'titulo': 'text', 'descripcion': 'text', 'fecha_asignada': 'date',
      'fecha_limite': 'date', 'completada_en': 'timestamptz', 'comentario_familia': 'text',
    });
    resumen['tareas para casa'] = tareas.length;
  }

  // ---------------------------------------------------------------------------
  // Desempeño, demanda, solicitudes y notificaciones
  // ---------------------------------------------------------------------------
  Future<void> _desempeno(_Lotes db, Session tx) async {
    final evaluaciones = <Map<String, Object?>>[];
    for (final m in _matriculas) {
      final umbral = m.prog.def.total - m.prog.def.antesEvaluacion;
      var consumidas = 0;
      DateTime? alcanzada;
      for (final p in m.sesiones) {
        if (p.asistencia == 'ASISTIO' || p.asistencia == 'FALTA') consumidas++;
        if (consumidas >= umbral) {
          alcanzada = p.sesion.inicio;
          break;
        }
      }
      if (alcanzada == null || _r.nextDouble() > 0.85) continue;
      final fecha = alcanzada.add(const Duration(days: 1, hours: 20));
      if (!fecha.isBefore(hoy)) continue;
      final conteo = <_Prof, int>{};
      for (final p in m.sesiones.where((p) => p.asistencia == 'ASISTIO')) {
        conteo[p.sesion.prof] = (conteo[p.sesion.prof] ?? 0) + 1;
      }
      if (conteo.isEmpty) continue;
      final prof = (conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      final puntaje = (prof.calidad + _gauss() * 0.7).round().clamp(1, 5);
      evaluaciones.add({
        'matricula_id': m.id, 'profesional_id': prof.id, 'representante_id': m.paciente.reps.first.id,
        'puntaje': puntaje, 'comentario': _elegir(comentariosEvaluacion), 'evaluado_en': _ts(fecha),
      });
    }
    await db.insertar('desempeno.evaluaciones_terapeuta', evaluaciones, {
      'matricula_id': 'uuid', 'profesional_id': 'uuid', 'representante_id': 'uuid', 'puntaje': 'smallint',
      'comentario': 'text', 'evaluado_en': 'timestamptz',
    });
    resumen['evaluaciones de familias a terapeutas'] = evaluaciones.length;

    final politica = _id();
    await db.insertar('desempeno.politicas_bono', [
      {'id': politica, 'nombre': 'Bono de desempeño mensual (ejemplo)', 'monto_base': 100, 'periodicidad': 'MENSUAL',
       'minimo_evaluaciones': 2, 'vigente_desde': _f(DateTime.utc(hoy.year, 1, 1))},
    ], {'id': 'uuid', 'nombre': 'text', 'monto_base': 'numeric', 'periodicidad': 'text', 'minimo_evaluaciones': 'smallint', 'vigente_desde': 'date'});
    await db.insertar('desempeno.bono_niveles', [
      for (final (minimo, pct) in const [(4.5, 100), (3.5, 80), (2.5, 50), (1.5, 20), (0.0, 10)])
        {'politica_id': politica, 'puntaje_min': minimo, 'porcentaje': pct},
    ], {'politica_id': 'uuid', 'puntaje_min': 'numeric', 'porcentaje': 'numeric'});
    for (var i = 4; i >= 0; i--) {
      final inicio = DateTime.utc(hoy.year, hoy.month - i, 1);
      final fin = DateTime.utc(inicio.year, inicio.month + 1, 0);
      await tx.execute(
        Sql.named('SELECT desempeno.calcular_bonos(CAST(@p:text AS uuid), CAST(@i:text AS date), CAST(@f:text AS date))'),
        parameters: {'p': politica, 'i': _f(inicio), 'f': _f(fin)},
      );
    }
  }

  Future<void> _demandaYSolicitudes(_Lotes db) async {
    final niveles = <String>[];
    for (final f in await db.tx.execute('SELECT id::text FROM personas.niveles_demanda ORDER BY orden')) {
      niveles.add(f[0]! as String);
    }
    final clasificables = _pacientes.where((p) => !p.prospecto).toList()..shuffle(_r);
    final elegidos = clasificables.take((clasificables.length * 0.4).round()).toList();
    final anteriores = <Map<String, Object?>>[];
    final vigentes = <Map<String, Object?>>[];
    for (final p in elegidos) {
      final nivel = _elegirPeso(niveles, const [40, 35, 18, 7]);
      if (_r.nextDouble() < 0.15) {
        anteriores.add({
          'paciente_id': p.id, 'nivel_id': _elegir(niveles), 'motivo': _elegir(motivosDemanda),
          'clasificado_por': _elegir(_coordinadores), 'clasificado_en': _ts(hoy.subtract(Duration(days: _entre(60, 120)))),
        });
      }
      vigentes.add({
        'paciente_id': p.id, 'nivel_id': nivel, 'motivo': _elegir(motivosDemanda),
        'clasificado_por': _elegir(_coordinadores), 'clasificado_en': _ts(hoy.subtract(Duration(days: _entre(1, 50)))),
      });
    }
    const tipos = {'paciente_id': 'uuid', 'nivel_id': 'uuid', 'motivo': 'text', 'clasificado_por': 'uuid', 'clasificado_en': 'timestamptz'};
    await db.insertar('personas.clasificaciones_demanda', anteriores, tipos);
    await db.insertar('personas.clasificaciones_demanda', vigentes, tipos);
    resumen['clasificaciones de demanda'] = anteriores.length + vigentes.length;

    final futuras = _sesiones
        .where((s) => s.tipo == 'PROGRAMA' && s.participantes.length == 1 && s.estado == 'PROGRAMADA' &&
            s.inicio.isBefore(hoy.add(const Duration(days: 21))))
        .toList()
      ..shuffle(_r);
    final solicitudes = <Map<String, Object?>>[];
    for (final (i, s) in futuras.take(25).indexed) {
      final part = s.participantes.first;
      final estado = i < 12 ? 'PENDIENTE' : i < 20 ? 'APROBADA' : 'RECHAZADA';
      final familia = _r.nextDouble() < 0.8;
      solicitudes.add({
        'participante_id': part.id,
        'solicitado_por': familia ? part.paciente.reps.first.usuarioId : s.prof.usuarioId,
        'origen': familia ? 'FAMILIA' : 'CENTRO', 'tipo': _r.nextDouble() < 0.75 ? 'REPROGRAMAR' : 'CANCELAR',
        'motivo': familia ? _elegir(const ['Cita médica', 'Viaje', 'Enfermedad', 'Evento escolar']) : 'Capacitación del terapeuta',
        'propuesta_inicio': _ts(s.inicio.add(Duration(days: _entre(1, 4)))),
        'estado': estado,
        'resuelto_por': estado == 'PENDIENTE' ? null : _elegir(_coordinadores),
        'resuelto_en': estado == 'PENDIENTE' ? null : _ts(hoy.subtract(Duration(days: _entre(0, 3)))),
        'creado_en': _ts(hoy.subtract(Duration(days: _entre(0, 5)))),
      });
    }
    await db.insertar('agenda.solicitudes_cambio', solicitudes, {
      'participante_id': 'uuid', 'solicitado_por': 'uuid', 'origen': 'text', 'tipo': 'text', 'motivo': 'text',
      'propuesta_inicio': 'timestamptz', 'estado': 'text', 'resuelto_por': 'uuid', 'resuelto_en': 'timestamptz', 'creado_en': 'timestamptz',
    });
    resumen['solicitudes de cambio'] = solicitudes.length;
  }

  Future<void> _notificaciones(_Lotes db) async {
    final dispositivos = <Map<String, Object?>>[];
    for (final u in _usuarios) {
      if (_r.nextDouble() > 0.6) continue;
      dispositivos.add({
        'usuario_id': u['id'], 'plataforma': _elegirPeso(const ['ANDROID', 'IOS', 'WEB'], const [65, 25, 10]),
        'token_push': 'token-de-prueba-${_id()}', 'ultimo_uso': _ts(hoy.subtract(Duration(days: _entre(0, 20)))),
      });
    }
    await db.insertar('notificaciones.dispositivos', dispositivos,
        {'usuario_id': 'uuid', 'plataforma': 'text', 'token_push': 'text', 'ultimo_uso': 'timestamptz'});

    final avisos = <Map<String, Object?>>[];
    for (final s in _sesiones.where((s) => s.estado != 'CANCELADA' && !s.inicio.isBefore(hoy.subtract(const Duration(days: 2))) &&
        s.inicio.isBefore(hoy.add(const Duration(days: 3))))) {
      for (final part in s.participantes) {
        final programada = s.inicio.subtract(const Duration(days: 1));
        avisos.add({
          'usuario_id': part.paciente.reps.first.usuarioId, 'canal': 'PUSH', 'tipo': 'RECORDATORIO_SESION',
          'titulo': 'Sesión de mañana', 'cuerpo': '${part.paciente.nombres.split(' ').first} tiene sesión a las ${_2(s.inicio.hour)}:00.',
          'datos': {'sesion_id': s.id}, 'programada_para': _ts(programada),
          'enviada_en': programada.isBefore(hoy) ? _ts(programada) : null,
          'leida_en': programada.isBefore(hoy) && _r.nextBool() ? _ts(programada.add(const Duration(hours: 2))) : null,
        });
      }
    }
    await db.insertar('notificaciones.notificaciones', avisos, {
      'usuario_id': 'uuid', 'canal': 'text', 'tipo': 'text', 'titulo': 'text', 'cuerpo': 'text', 'datos': 'jsonb',
      'programada_para': 'timestamptz', 'enviada_en': 'timestamptz', 'leida_en': 'timestamptz',
    });
    resumen['notificaciones'] = avisos.length;
  }

  Future<void> _indicadores(Session tx) async {
    final mes = _f(DateTime.utc(hoy.year, hoy.month, 1));
    await tx.execute(Sql.named('''
      INSERT INTO reportes.metas (indicador_id, sede_id, periodo, valor_meta)
      SELECT i.id, s.id, CAST(@mes:text AS date), m.valor
      FROM (VALUES ('SATURACION_SEDE', 75), ('ASISTENCIA_30D', 90), ('CONTRATOS_POR_VENCER', 10)) AS m(codigo, valor)
      JOIN reportes.indicadores i ON i.codigo = m.codigo
      CROSS JOIN organizacion.sedes s'''), parameters: {'mes': mes});
    final r = await tx.execute(Sql.named('''
      SELECT sum(reportes.calcular_indicadores(d::date))
      FROM generate_series(CAST(@desde:text AS date), CAST(@hasta:text AS date), interval '1 day') d'''),
        parameters: {'desde': _f(hoy.subtract(const Duration(days: 29))), 'hasta': _f(hoy)});
    resumen['valores de indicadores (30 días)'] = int.parse(r.first.first.toString());
  }

  // ---------------------------------------------------------------------------
  // Disponibilidad
  // ---------------------------------------------------------------------------
  static int _k(DateTime t) => t.millisecondsSinceEpoch ~/ 3600000;

  bool _profLibre(_Prof p, DateTime t) {
    final horas = p.horas[t.weekday];
    if (horas == null || !horas.contains(t.hour)) return false;
    if (_feriados.contains(_f(t))) return false;
    for (final (ini, fin, _) in p.ausencias) {
      if (!t.isBefore(ini) && t.isBefore(fin)) return false;
    }
    return !_ocupProf[p.id]!.contains(_k(t));
  }

  bool _pacLibre(_Paciente p, DateTime t) => !_ocupPac[p.id]!.contains(_k(t));
  void _ocupar(_Prof p, DateTime t) => _ocupProf[p.id]!.add(_k(t));
  void _ocuparPac(_Paciente p, DateTime t) => _ocupPac[p.id]!.add(_k(t));

  List<DateTime> _generarFechas({
    required DateTime desde,
    required List<Franja> patron,
    required int cantidad,
    required bool Function(DateTime) disponible,
    Set<String> bloqueadas = const {},
  }) {
    final fechas = <DateTime>[];
    var d = desde;
    for (var i = 0; i < 400 && fechas.length < cantidad; i++) {
      for (final (dia, hora) in patron) {
        if (d.weekday != dia || bloqueadas.contains(_f(d))) continue;
        final t = DateTime.utc(d.year, d.month, d.day, hora);
        if (disponible(t)) {
          fechas.add(t);
          break;
        }
      }
      d = d.add(const Duration(days: 1));
    }
    return fechas;
  }

  _Prof _profMenosCargado(_Sede sede, String sub, DateTime desde) {
    final candidatos = _profs.where((p) => p.sede == sede && p.subAreas.contains(sub)).toList()..shuffle(_r);
    final ventana = {for (var i = 0; i < 28 * 24; i++) _k(desde) + i};
    candidatos.sort((a, b) => _ocupProf[a.id]!.where(ventana.contains).length.compareTo(_ocupProf[b.id]!.where(ventana.contains).length));
    return candidatos.first;
  }

  List<Franja> _elegirPatron(_Prof prof, _Paciente pac, DateTime desde, int porSemana) {
    final dias = prof.horas.keys.where((d) => d <= 5).toList();
    List<Franja>? mejor;
    var menorConflicto = 1 << 30;
    for (var intento = 0; intento < 30; intento++) {
      final elegidos = porSemana >= dias.length ? dias : (dias.toList()..shuffle(_r)).take(porSemana).toList()
        ..sort();
      final comunes = prof.horas[elegidos.first]!.where((h) => elegidos.every((d) => prof.horas[d]!.contains(h))).toList();
      if (comunes.isEmpty) continue;
      final hora = comunes[_r.nextInt(comunes.length)];
      final patron = [for (final d in elegidos) (d, hora)];
      var conflictos = 0;
      for (var i = 0; i < 28; i++) {
        final d = desde.add(Duration(days: i));
        for (final (dia, h) in patron) {
          if (d.weekday != dia) continue;
          final t = DateTime.utc(d.year, d.month, d.day, h);
          if (!_profLibre(prof, t) || !_pacLibre(pac, t)) conflictos++;
        }
      }
      if (conflictos < menorConflicto) {
        menorConflicto = conflictos;
        mejor = patron;
        if (conflictos == 0) break;
      }
    }
    return mejor ?? [(1, prof.horas[1]!.first)];
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------
  String _id() => _uuid.v4();
  T _elegir<T>(List<T> lista) => lista[_r.nextInt(lista.length)];
  int _entre(int a, int b) => a + _r.nextInt(b - a + 1);
  String _digitos(int n) => List.generate(n, (_) => _r.nextInt(10)).join();
  double _gauss() => sqrt(-2 * log(1 - _r.nextDouble())) * cos(2 * pi * _r.nextDouble());
  String _apellidos() => '${_elegir(apellidosLista)} ${_elegir(apellidosLista)}';
  List<String> get apellidosLista => apellidos;

  T _elegirPeso<T>(List<T> lista, List<int> pesos) {
    final total = pesos.fold<int>(0, (a, b) => a + b);
    var x = _r.nextInt(total);
    for (var i = 0; i < lista.length; i++) {
      x -= pesos[i];
      if (x < 0) return lista[i];
    }
    return lista.last;
  }

  /// Cédula ficticia: prefijo 99 (provincia inexistente) para no coincidir con nadie.
  String _cedula() {
    String c;
    do {
      c = '99${_digitos(8)}';
    } while (!_cedulas.add(c));
    return c;
  }

  DateTime _lunes(DateTime d) => _soloFecha(d).subtract(Duration(days: d.weekday - 1));

  DateTime _diaHabil(DateTime d) {
    var x = _soloFecha(d);
    while (x.weekday > 5 || _feriados.contains(_f(x))) {
      x = x.add(const Duration(days: 1));
    }
    return x;
  }

  static DateTime _soloFecha(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  static String _2(int n) => n.toString().padLeft(2, '0');
  static String _f(DateTime d) => '${d.year}-${_2(d.month)}-${_2(d.day)}';
  static String _ts(DateTime d) => '${_f(d)} ${_2(d.hour)}:${_2(d.minute)}:00-05:00';

  static String _slug(String s) {
    const mapa = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u'};
    return s.toLowerCase().split('').map((c) => mapa[c] ?? c).join().replaceAll(RegExp('[^a-z0-9]'), '');
  }
}

// -----------------------------------------------------------------------------
// Inserción por lotes con jsonb_to_recordset: una consulta por cada 1000 filas.
// -----------------------------------------------------------------------------
class _Lotes {
  _Lotes(this.tx, this.llave, this.resumen);

  final Session tx;
  final String llave;
  final Map<String, int> resumen;

  Future<void> insertar(
    String tabla,
    List<Map<String, Object?>> filas,
    Map<String, String> tipos, {
    Map<String, String> expresiones = const {},
  }) async {
    if (filas.isEmpty) return;
    final columnasJson = tipos.keys.toList();
    final destino = {...columnasJson, ...expresiones.keys}.toList();
    final definicion = columnasJson.map((c) => '"$c" ${tipos[c]}').join(', ');
    final valores = destino.map((c) => expresiones[c] ?? 'x."$c"').join(', ');
    final usaLlave = expresiones.values.any((e) => e.contains('@llave'));
    for (var i = 0; i < filas.length; i += 1000) {
      final lote = filas.sublist(i, min(i + 1000, filas.length));
      await tx.execute(
        Sql.named(
          'INSERT INTO $tabla (${destino.map((c) => '"$c"').join(', ')}) '
          'SELECT $valores FROM jsonb_to_recordset(CAST(@datos:text AS jsonb)) AS x($definicion)',
        ),
        parameters: {'datos': jsonEncode(lote), if (usaLlave) 'llave': llave},
      );
    }
  }

  Future<void> actualizar(String tabla, List<Map<String, Object?>> filas, Map<String, String> tipos) async {
    if (filas.isEmpty) return;
    final definicion = ['"id" uuid', ...tipos.entries.map((e) => '"${e.key}" ${e.value}')].join(', ');
    final asignaciones = tipos.keys.map((c) => '"$c" = x."$c"').join(', ');
    for (var i = 0; i < filas.length; i += 1000) {
      final lote = filas.sublist(i, min(i + 1000, filas.length));
      await tx.execute(
        Sql.named(
          'UPDATE $tabla t SET $asignaciones '
          'FROM jsonb_to_recordset(CAST(@datos:text AS jsonb)) AS x($definicion) WHERE t.id = x.id',
        ),
        parameters: {'datos': jsonEncode(lote)},
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Modelos internos del generador
// -----------------------------------------------------------------------------
class _Sede {
  _Sede(this.id, this.codigo);
  final String id;
  final String codigo;
  final salas = <String, String>{};
}

class _ProgDef {
  const _ProgDef(this.codigo, this.nombre, this.area, this.tipo, this.sub, this.total, this.meses, this.porSemana,
      this.modalidad, this.entrega, this.cupo, this.requiereValoracion, this.antesEvaluacion, this.precio, this.fases);
  final String codigo, nombre, area, tipo, sub, modalidad, entrega;
  final int total, cupo, antesEvaluacion;
  final int? meses, porSemana;
  final bool requiereValoracion;
  final double precio;
  final List<(String, int, String?)> fases;
}

class _Prog {
  _Prog(this.id, this.def);
  final String id;
  final _ProgDef def;
  final fases = <_Fase>[];
}

class _Fase {
  _Fase(this.id, this.sesiones, this.sub);
  final String id;
  final int sesiones;
  final String? sub;
}

class _Prof {
  _Prof({
    required this.id, required this.usuarioId, required this.sede, required this.subAreas, required this.nombres,
    required this.apellidos, required this.profesion, required this.color, required this.manana, required this.horas,
    required this.calidad,
  });
  final String id, usuarioId, nombres, apellidos, profesion, color;
  final _Sede sede;
  final List<String> subAreas;
  final bool manana;
  final Map<int, List<int>> horas;
  final double calidad;
  final ausencias = <(DateTime, DateTime, String)>[];
}

class _Rep {
  _Rep(this.id, this.usuarioId, this.nombres, this.apellidos, this.parentesco, this.cedula, this.apellidoPadre,
      this.apellidoMadre, this.direccion, this.sede);
  final String id, usuarioId, nombres, apellidos, parentesco, cedula, apellidoPadre, apellidoMadre, direccion;
  final _Sede sede;
}

class _Paciente {
  _Paciente({
    required this.id, required this.historia, required this.nombres, required this.apellidos, required this.sexo,
    required this.sede, required this.direccion, required this.cedula, required this.reps,
  });
  final String id, historia, nombres, apellidos, sexo, direccion, cedula;
  final _Sede sede;
  final List<_Rep> reps;
  late DateTime nacimiento;
  var prospecto = false;
  var estado = 'ACTIVO';
  final matriculas = <_Mat>[];
}

class _Contrato {
  _Contrato(this.id, this.codigo, this.rep, this.sede, this.tipo, this.valor, this.firma, this.desde, this.hasta, this.matriculas);
  final String id, codigo, tipo;
  final _Rep rep;
  final _Sede sede;
  final double valor;
  final DateTime firma, desde, hasta;
  final List<_Mat> matriculas;
}

class _Mat {
  _Mat(this.id, this.paciente, this.prog, this.inicio);
  final String id;
  final _Paciente paciente;
  final _Prog prog;
  DateTime inicio;
  DateTime? finEstimado;
  _Cohorte? cohorte;
  _Contrato? contrato;
  List<Franja>? patron;
  String? planId;
  DateTime? retiroDesde;
  (DateTime, DateTime)? congelamiento;
  var estado = 'EN_CURSO';
  final sesiones = <_Part>[];
}

class _Cohorte {
  _Cohorte({
    required this.id, required this.codigo, required this.prog, required this.sede, required this.prof,
    required this.salaId, required this.cupo, required this.objetivo, required this.inicio, required this.patron,
  });
  final String id, codigo, salaId;
  final _Prog prog;
  final _Sede sede;
  final _Prof prof;
  final int cupo, objetivo;
  final DateTime inicio;
  final List<Franja> patron;
  final miembros = <_Mat>[];
}

class _Sesion {
  _Sesion(this.id, this.sede, this.prof, this.prog, this.tipo, this.inicio, this.cupo);
  final String id, tipo;
  final _Sede sede;
  final _Prof prof;
  final _Prog? prog;
  final DateTime inicio;
  final int cupo;
  _Cohorte? grupo;
  _Mat? plan;
  String? salaId;
  String entrega = 'PRESENCIAL';
  String estado = 'PROGRAMADA';
  String? motivo;
  final participantes = <_Part>[];
}

class _Part {
  _Part(this.id, this.sesion, this.paciente, this.mat, this.numero);
  final String id;
  final _Sesion sesion;
  final _Paciente paciente;
  final _Mat? mat;
  final int numero;
  String? faseId;
  String asistencia = 'PENDIENTE';
}
