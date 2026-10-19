import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

import '../../../core/util/formatos.dart';
import 'agenda.dart';
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
        participantes: [for (final p in listaJson(j['participantes'])) ParticipanteCita.fromJson(p)],
      );

  final String id, tipo, estado, fecha, inicio, fin, sede;
  final int cupo;
  final String? programa, grupo;
  final List<ParticipanteCita> participantes;

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

/// Lo que hay en un turno (o una pausa) de un día del horario.
class Celda {
  const Celda(this.tipo, {this.texto, this.sesion});

  final TipoCelda tipo;
  final String? texto;
  final SesionHorario? sesion;
}

/// Un turno o una pausa de un día, de [inicio] a [fin] en minutos desde medianoche.
class FranjaHorario {
  const FranjaHorario(this.inicio, this.fin, this.celda);

  final int inicio, fin;
  final Celda celda;

  String get hora => '${hhmm(inicio)}–${hhmm(fin)}';
}

/// 545 → "09:05".
String hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Semana de un profesional: jornadas, pausas, ausencias y sesiones.
class ProfesionalSemana {
  const ProfesionalSemana({
    required this.id,
    required this.nombre,
    required this.profesion,
    required this.color,
    required this.minutosTurno,
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
        minutosTurno: (j['minutos_turno'] as int?) ?? 60,
        jornadas: [for (final x in listaJson(j['jornadas'])) JornadaDia.fromJson(x)],
        pausas: [for (final x in listaJson(j['pausas'])) PausaDia.fromJson(x)],
        ausencias: [for (final x in listaJson(j['ausencias'])) Ausencia.fromJson(x)],
        sesiones: [for (final x in listaJson(j['sesiones'])) SesionHorario.fromJson(x)],
      );

  final String id, nombre, profesion;
  final Color color;

  /// Cada cuánto empieza un turno: 60 en Neuro (45 de sesión y 15 de
  /// descanso), 45 en Terapia de lenguaje (seguidos).
  final int minutosTurno;
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

  /// Turnos y pausas de [fecha], como en la hoja de horarios de Coordinación.
  /// Los turnos se cuentan desde el inicio de la jornada cada [minutosTurno];
  /// si uno choca con una pausa, se vuelve a contar desde el final de la pausa
  /// (igual que la API). Las sesiones fuera de turno también se muestran.
  List<FranjaHorario> franjasDel(DateTime fecha, List<Feriado> feriados) {
    final dia = fecha.weekday;
    final pausasDia = pausas.where((p) => p.dia == dia).toList();
    final franjas = <FranjaHorario>[];
    for (final j in jornadasDel(dia)) {
      final fin = minutos(j.fin);
      var m = minutos(j.inicio);
      while (m + minutosTurno <= fin) {
        final pausa = pausasDia.where((p) => m < minutos(p.fin) && m + minutosTurno > minutos(p.inicio)).firstOrNull;
        if (pausa != null) {
          m = minutos(pausa.fin);
          continue;
        }
        franjas.add(FranjaHorario(m, m + minutosTurno, _celda(fecha, j, m, m + minutosTurno, feriados)));
        m += minutosTurno;
      }
      for (final p in pausasDia.where((p) => minutos(p.inicio) < fin && minutos(p.fin) > minutos(j.inicio))) {
        franjas.add(FranjaHorario(minutos(p.inicio), minutos(p.fin), Celda(TipoCelda.pausa, texto: Formatos.etiqueta(p.tipo))));
      }
    }
    for (final s in sesionesDel(fecha)) {
      if (!franjas.any((x) => x.celda.sesion?.id == s.id)) {
        franjas.add(FranjaHorario(minutos(s.inicio), minutos(s.fin), Celda(TipoCelda.sesion, sesion: s)));
      }
    }
    return franjas..sort((a, b) => a.inicio.compareTo(b.inicio));
  }

  Celda _celda(DateTime fecha, JornadaDia jornada, int ini, int fin, List<Feriado> feriados) {
    final f = Formatos.fechaIso(fecha);
    final feriado = feriados.where((x) => x.fecha == f && (x.sede == null || x.sede == jornada.sede)).firstOrNull;
    if (feriado != null) return Celda(TipoCelda.feriado, texto: feriado.nombre);
    final ausencia = ausenciaEn('${f}T${hhmm(ini)}', '${f}T${hhmm(fin)}');
    if (ausencia != null) return Celda(TipoCelda.ausencia, texto: Formatos.etiqueta(ausencia.tipo));
    final sesion = sesiones.where((s) => s.fecha == f && minutos(s.inicio) < fin && minutos(s.fin) > ini).firstOrNull;
    if (sesion != null) return Celda(TipoCelda.sesion, sesion: sesion);
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
}
