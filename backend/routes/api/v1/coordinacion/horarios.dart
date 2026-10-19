import 'package:backend/core/auth/sesion.dart';
import 'package:backend/core/dependencias.dart';
import 'package:backend/core/http/respuestas.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/coordinacion/horarios?semana=AAAA-MM-DD&area&sede&profesional
/// → horario de lunes a sábado de la semana de esa fecha: jornadas, pausas,
///   ausencias y sesiones de cada profesional, más los feriados.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return metodoNoPermitido();
  return conErrores(() async {
    final q = context.request.uri.queryParameters;
    return Response.json(
      body: await context.read<Dependencias>().coordinacion.agenda.semana(
            context.read<Sesion>(),
            fecha: q['semana'] ?? DateTime.now().toIso8601String().substring(0, 10),
            area: q['area'],
            sede: q['sede'],
            profesional: q['profesional'],
          ),
    );
  });
}
