import 'package:intl/intl.dart';

/// Formatos de fechas, horas y edades usados en toda la app.
class Formatos {
  const Formatos._();

  static String fechaIso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// "sábado 17 de octubre"
  static String fechaLarga(DateTime d) => DateFormat("EEEE d 'de' MMMM", 'es').format(d);

  /// "17 oct 2026" a partir de "2026-10-17" o "2026-10-17T09:00".
  static String fechaCorta(String? iso) {
    final d = _leer(iso);
    return d == null ? '—' : DateFormat('d MMM yyyy', 'es').format(d);
  }

  /// "09:00" a partir de "2026-10-17T09:00".
  static String hora(String? iso) {
    if (iso == null || iso.length < 16) return '—';
    return iso.substring(11, 16);
  }

  /// "sáb 17 oct, 09:00"
  static String fechaHora(String? iso) {
    final d = _leer(iso);
    return d == null ? '—' : DateFormat("EEE d MMM, HH:mm", 'es').format(d);
  }

  /// "8 meses" o "4 años".
  static String edad(int? meses) {
    if (meses == null) return '—';
    if (meses < 24) return '$meses ${meses == 1 ? 'mes' : 'meses'}';
    return '${meses ~/ 12} años';
  }

  static String dinero(num? valor) => valor == null ? '—' : NumberFormat.currency(locale: 'es', symbol: r'$').format(valor);

  static String numero(num? valor, {int decimales = 0}) =>
      valor == null ? '—' : NumberFormat.decimalPatternDigits(locale: 'es', decimalDigits: decimales).format(valor);

  /// Etiqueta legible de los valores en mayúsculas de la base: "FALTA_JUSTIFICADA" → "Falta justificada".
  static String etiqueta(String? valor) {
    if (valor == null || valor.isEmpty) return '—';
    final t = valor.replaceAll('_', ' ').toLowerCase();
    return t[0].toUpperCase() + t.substring(1);
  }

  static DateTime? _leer(String? iso) => iso == null ? null : DateTime.tryParse(iso.replaceFirst(' ', 'T'));
}
