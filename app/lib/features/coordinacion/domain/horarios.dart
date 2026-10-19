import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

import '../../../core/util/formatos.dart';
import 'contexto.dart';
import 'profesionales.dart';

/// Minutos desde medianoche de "HH:MM".
int minutos(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

class JornadaDia {
  const JornadaDia({required this.dia, required this.sede, required this.inicio, required this.fin});

  factory JornadaDia.fromJson(Map<String, dynamic> j) =>
      JornadaDia(dia: j['dia'] as int, sede: j['sede'] as String, inicio: j['inicio'] as String, fin: j['fin'] as String);

  final int dia;
  final String sede, inicio, fin;
}

class PausaDia {
  const PausaDia({required this.dia, required this.tipo, required this.inicio, required this.fin});

  factory PausaDia.fromJson(Map<String, dynamic> j) =>
      PausaDia(dia: j['dia'] as int, tipo: j['tipo'] as String, inicio: j['inicio'] as String, fin: j['fin'] as String);

  final int dia;
  final String tipo, inicio, fin;
}

/// Ausencia con fechas y horas locales "AAAA-MM-DDTHH:MM".
class Ausencia {
  const Ausencia({required this.tipo, required this.desde, required this.hasta});

  factory Ausencia.fromJson(Map<String, dynamic> j) =>
      Ausencia(tipo: j['tipo'] as String, desde: j['desde'] as String, hasta: j['hasta'] as String);

  final String tipo, desde, hasta;
}

class SesionHorario {
  const SesionHorario({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.fecha,
    required this.inicio,
    required this.fin,
    required this.sede,
    required this.cupo,
    required this.participantes,
    this.programa,
    this.grupo,
  });

  factory SesionHorario.fromJson(Map<String, dynamic> j) => SesionHorario(
        id: j['id'] as String,
        tipo: j['tipo'] as String,
        estado: j['estado'] as String,
        fecha: j['fecha'] as String,
        inicio: j['inicio'] as String,
        fin: j['fin'] as String,
        sede: j['sede'] as String,
        cupo: j['cupo'] as int,
        programa: j['programa'] as String?,
        grupo: j['grupo'] as String?,
        participantes: (j['participantes'] as List).cast<String>(),
      );

  final String id, tipo, estado, fecha, inicio, fin, sede;
  final int cupo;
  final String? programa, grupo;
  final List<String> participantes;

  String get titulo => programa ?? Formatos.etiqueta(tipo);
  double get horas => (minutos(fin) - minutos(inicio)) / 60;
}

class Feriado {
  const Feriado({required this.fecha, required this.nombre, this.sede});

  factory Feriado.fromJson(Map<String, dynamic> j) =>
      Feriado(fecha: j['fecha'] as String, nombre: j['nombre'] as String, sede: j['sede'] as String?);

  final String fecha, nombre;
  final String? sede;
}

enum TipoCelda { fuera, libre, pausa, ausencia, feriado, sesion }

/// Lo que hay en una hora de un día del horario.
class Celda {
  const Celda(this.tipo, {this.texto, this.sesion});

  final TipoCelda tipo;
  final String? texto;
  final SesionHorario? sesion;
}

/// Semana de un profesional: jornadas, pausas, ausencias y sesiones.
class ProfesionalSemana {
  const ProfesionalSemana({
    required this.id,
    required this.nombre,
    required this.profesion,
    required this.color,
    required this.jornadas,
    required this.pausas,
    required this.ausencias,
    required this.sesiones,
  });

  factory ProfesionalSemana.fromJson(Map<String, dynamic> j) => ProfesionalSemana(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        profesion: j['profesion'] as String,
        color: colorDe(j['color'] as String?),
        jornadas: [for (final x in listaJson(j['jornadas'])) JornadaDia.fromJson(x)],
        pausas: [for (final x in listaJson(j['pausas'])) PausaDia.fromJson(x)],
        ausencias: [for (final x in listaJson(j['ausencias'])) Ausencia.fromJson(x)],
        sesiones: [for (final x in listaJson(j['sesiones'])) SesionHorario.fromJson(x)],
      );

  final String id, nombre, profesion;
  final Color color;
  final List<JornadaDia> jornadas;
  final List<PausaDia> pausas;
  final List<Ausencia> ausencias;
  final List<SesionHorario> sesiones;

  List<JornadaDia> jornadasDel(int dia) => jornadas.where((j) => j.dia == dia).toList();

  List<SesionHorario> sesionesDel(DateTime fecha) {
    final f = Formatos.fechaIso(fecha);
    return sesiones.where((s) => s.fecha == f).toList();
  }

  /// Horas de trabajo del día sin contar las pausas.
  double horasDel(int dia) {
    var total = 0;
    for (final j in jornadasDel(dia)) {
      total += minutos(j.fin) - minutos(j.inicio);
      for (final p in pausas.where((p) => p.dia == dia)) {
        final cruce = _cruce(minutos(j.inicio), minutos(j.fin), minutos(p.inicio), minutos(p.fin));
        total -= cruce;
      }
    }
    return total / 60;
  }

  Ausencia? ausenciaEn(String desde, String hasta) =>
      ausencias.where((a) => a.desde.compareTo(hasta) < 0 && a.hasta.compareTo(desde) > 0).firstOrNull;

  /// Qué hay de [hora]:00 a [hora+1]:00 en [fecha].
  Celda celda(DateTime fecha, int hora, List<Feriado> feriados) {
    final ini = hora * 60, fin = ini + 60;
    final f = Formatos.fechaIso(fecha);
    final jornada = jornadas.where((j) => j.dia == fecha.weekday && minutos(j.inicio) <= ini && minutos(j.fin) >= fin).firstOrNull;
    final sesion = sesiones.where((s) => s.fecha == f && minutos(s.inicio) < fin && minutos(s.fin) > ini).firstOrNull;
    if (jornada == null && sesion == null) return const Celda(TipoCelda.fuera);
    final feriado = feriados.where((x) => x.fecha == f && (x.sede == null || x.sede == jornada?.sede)).firstOrNull;
    if (feriado != null) return Celda(TipoCelda.feriado, texto: feriado.nombre);
    String dos(int h) => h.toString().padLeft(2, '0');
    final ausencia = ausenciaEn('${f}T${dos(hora)}:00', '${f}T${dos(hora + 1)}:00');
    if (ausencia != null) return Celda(TipoCelda.ausencia, texto: Formatos.etiqueta(ausencia.tipo));
    if (sesion != null) return Celda(TipoCelda.sesion, sesion: sesion);
    final pausa = pausas.where((p) => p.dia == fecha.weekday && minutos(p.inicio) < fin && minutos(p.fin) > ini).firstOrNull;
    if (pausa != null) return Celda(TipoCelda.pausa, texto: Formatos.etiqueta(pausa.tipo));
    return const Celda(TipoCelda.libre);
  }

  static int _cruce(int a1, int a2, int b1, int b2) => math.max(0, math.min(a2, b2) - math.max(a1, b1));
}

/// Horario de lunes a sábado de varios profesionales.
class SemanaHorario {
  const SemanaHorario({required this.desde, required this.hasta, required this.feriados, required this.profesionales});

  factory SemanaHorario.fromJson(Map<String, dynamic> j) => SemanaHorario(
        desde: DateTime.parse(j['desde'] as String),
        hasta: DateTime.parse(j['hasta'] as String),
        feriados: [for (final x in listaJson(j['feriados'])) Feriado.fromJson(x)],
        profesionales: [for (final x in listaJson(j['profesionales'])) ProfesionalSemana.fromJson(x)],
      );

  final DateTime desde, hasta;
  final List<Feriado> feriados;
  final List<ProfesionalSemana> profesionales;

  /// Los seis días de la semana (lunes a sábado).
  List<DateTime> get dias => [for (var i = 0; i < 6; i++) DateTime(desde.year, desde.month, desde.day + i)];

  Feriado? feriadoDel(DateTime dia) {
    final f = Formatos.fechaIso(dia);
    return feriados.where((x) => x.fecha == f).firstOrNull;
  }

  /// Primera y última hora con jornada o sesión (por defecto 8 a 18).
  (int, int) rangoHoras(Iterable<ProfesionalSemana> profesionales) {
    var desde = 24, hasta = 0;
    for (final p in profesionales) {
      for (final (inicio, fin) in [for (final j in p.jornadas) (j.inicio, j.fin), for (final s in p.sesiones) (s.inicio, s.fin)]) {
        desde = math.min(desde, minutos(inicio) ~/ 60);
        hasta = math.max(hasta, (minutos(fin) + 59) ~/ 60);
      }
    }
    return desde >= hasta ? (8, 18) : (desde, hasta);
  }
}
