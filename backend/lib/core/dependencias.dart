import 'package:backend/core/auth/tokens.dart';
import 'package:backend/core/config.dart';
import 'package:backend/core/db/base_datos.dart';
import 'package:backend/core/db/conexion.dart';
import 'package:backend/modules/auth/auth_repositorio.dart';
import 'package:backend/modules/auth/auth_servicio.dart';
import 'package:backend/modules/coordinacion/coordinacion_servicio.dart';
import 'package:backend/modules/familias/familias_servicio.dart';
import 'package:backend/modules/gerencia/gerencia_servicio.dart';
import 'package:backend/modules/herramienta_datos/datos_servicio.dart';
import 'package:backend/modules/terapeuta/terapeuta_servicio.dart';

/// Tablas que el Administrador puede ver en su pantalla, y cuáles solo leer
/// (catálogos comunes a todas las empresas o datos calculados).
const tablasAdministracion = {
  'organizacion.sedes', 'organizacion.salas', 'organizacion.feriados', 'organizacion.rucs',
  'catalogo.areas', 'catalogo.sub_areas', 'catalogo.programas', 'catalogo.programa_fases', 'catalogo.tipos_programa',
  'personas.profesionales', 'personas.profesional_sub_areas', 'personas.niveles_demanda',
  'agenda.jornadas', 'agenda.pausas', 'agenda.ausencias',
  'seguridad.usuarios', 'seguridad.usuario_roles', 'seguridad.roles', 'seguridad.permisos', 'seguridad.rol_permisos',
  'desempeno.politicas_bono', 'desempeno.bono_niveles', 'desempeno.escala_evaluacion', 'desempeno.bonos_calculados',
  'clinico.plantillas_nota', 'reportes.indicadores', 'reportes.metas', 'comun.parametros',
};

const tablasAdministracionSoloLectura = {
  'catalogo.tipos_programa', 'personas.niveles_demanda', 'seguridad.roles', 'seguridad.permisos',
  'seguridad.rol_permisos', 'desempeno.escala_evaluacion', 'desempeno.bonos_calculados',
  'reportes.indicadores', 'comun.parametros',
};

/// Crea una sola vez los servicios de la API y los comparte entre peticiones.
class Dependencias {
  Dependencias._({
    required this.config,
    required this.db,
    required this.auth,
    required this.datosDesarrollo,
    required this.datosAdministracion,
    required this.terapeuta,
    required this.familias,
    required this.coordinacion,
    required this.gerencia,
  });

  factory Dependencias.crear() {
    final config = Config.cargar();
    final db = BaseDatos(crearPoolApp(config));
    final llave = config.llaveCifrado;
    return Dependencias._(
      config: config,
      db: db,
      auth: AuthServicio(db, AuthRepositorio(), Tokens(config.jwtSecreto)),
      datosDesarrollo: DatosServicio(db, llave),
      datosAdministracion: DatosServicio(
        db,
        llave,
        permitidas: tablasAdministracion,
        soloLectura: tablasAdministracionSoloLectura,
      ),
      terapeuta: TerapeutaServicio(db, llave),
      familias: FamiliasServicio(db),
      coordinacion: CoordinacionServicio(db, llave),
      gerencia: GerenciaServicio(db),
    );
  }

  final Config config;
  final BaseDatos db;
  final AuthServicio auth;
  final DatosServicio datosDesarrollo;
  final DatosServicio datosAdministracion;
  final TerapeutaServicio terapeuta;
  final FamiliasServicio familias;
  final CoordinacionServicio coordinacion;
  final GerenciaServicio gerencia;
}
