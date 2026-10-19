# iSmart Salud – Sistema de horarios

Aplicación multiplataforma para la gestión de agenda, pacientes y terapias de iSmart Salud
(áreas **Neuro estimulación** y **Estimulación temprana**, varias sedes).

Fuera de alcance por ahora: inglés y e-commerce.

## Arquitectura

| Capa | Tecnología | Carpeta |
|------|------------|---------|
| App (Android, iOS, Web, macOS) | Flutter / Dart | `app/` |
| API REST | Dart Frog (Dart) | `backend/` |
| Base de datos | PostgreSQL 17 | `backend/db/` |

Monolito modular: los mismos módulos existen en la app (`app/lib/features/<módulo>`),
en la API (`backend/lib/modules/<módulo>` + `backend/routes`) y en la base (un esquema por módulo).

La app **nunca** se conecta directamente a la base de datos: todo pasa por la API, que usa un
usuario de PostgreSQL con permisos mínimos.

### Módulos de la base de datos

| Esquema | Contenido |
|---------|-----------|
| `comun` | Parámetros del negocio y funciones compartidas (cifrado) |
| `organizacion` | Sedes, salas, feriados, geografía |
| `catalogo` | Áreas, especialidades, tipos de programa, programas y fases |
| `seguridad` | Usuarios, roles por sede y área, permisos, bitácora de auditoría |
| `personas` | Terapeutas, pacientes, representantes, nivel de demanda |
| `matriculas` | Contratos, matrículas, congelamientos |
| `agenda` | Jornadas, pausas, ausencias, grupos, sesiones, participantes, solicitudes de cambio |
| `clinico` | Valoraciones, notas de sesión (cifradas), objetivos, tareas para casa |
| `desempeno` | Evaluación del terapeuta por la familia y bono de desempeño |
| `notificaciones` | Dispositivos, avisos y preferencias |
| `reportes` | Indicadores, metas y valores diarios (sin acceso a datos clínicos) |

## Requisitos

- Flutter SDK (stable), que incluye Dart
- PostgreSQL 17
- Dart Frog CLI: `dart pub global activate dart_frog_cli`
- Servidor estático para la web: `dart pub global activate dhttpd`
- Android Studio (SDK de Android) para compilar en Android
- iOS / macOS: requiere una Mac con Xcode

## Puesta en marcha (desarrollo)

1. Copia `.env.example` como `.env` y completa los valores.
2. Crea la base, el usuario de la API, las migraciones y los datos ficticios:

   ```bash
   cd backend
   dart run tool/db.dart reiniciar
   ```

3. Enciende la API y la app con doble clic en `iniciar_dev.bat`
   (o `dart_frog dev` en `backend/` y `dhttpd --path build/web --port 5173` en `app/`).
   - App: http://localhost:5173
   - API: http://localhost:8080

## Multiempresa

La matriz y sus sucursales (que pueden tener otro rubro) comparten **una base y un enlace**,
pero no los datos. Cada tabla de negocio tiene `empresa_id` y PostgreSQL (Row Level Security)
solo deja ver y escribir los datos de la empresa activa. Al iniciar sesión, la API devuelve las
empresas a las que pertenece el usuario; si son varias, la app pide elegir una y la envía en
cada petición (cabecera `X-Empresa-Id`).

Datos de prueba: **iSmart Salud** (matriz) e **iSmart Cuenca (ejemplo)**, una sucursal ficticia
de psicopedagogía. La gerencia de la matriz tiene acceso a ambas.

## Interfaces por rol

| Rol | Pantalla | API |
|-----|----------|-----|
| Gerencia | Indicadores con evolución y fórmula; bonos de desempeño | `/api/v1/gerencia` |
| Administración | Configuración: sedes, programas, terapeutas, jornadas, usuarios y roles | `/api/v1/admin/datos` |
| Coordinación | Módulos: Agenda, Estudiantes, Horarios, Profesionales y Solicitudes (ver abajo) | `/api/v1/coordinacion` |
| Terapeuta | Agenda del día, asistencia, notas cifradas, ficha del paciente, tareas | `/api/v1/terapeuta` |
| Familias | Próximas sesiones, progreso, tareas, evaluación del terapeuta, contrato vigente | `/api/v1/familia` |

Todo lo de `/api/v1` exige sesión (JWT de 15 minutos que la app renueva sola). Cada carpeta de
rol en `backend/routes/api/v1` tiene un `_middleware.dart` que exige ese rol. Las interfaces son
sencillas a propósito: primero la estructura y las peticiones; el diseño visual viene después.

### Coordinación por módulos

Menú lateral (abajo en el celular). Cada módulo tiene su propia navegación: las fichas se abren
dentro del módulo y se vuelve con la flecha; tocar el módulo actual regresa a su pantalla principal.

| Módulo | Qué muestra | API |
|--------|-------------|-----|
| Agenda | Sesiones del día; desde cada una se abre el profesional o el estudiante, o se cancela | `agenda`, `sesiones` |
| Estudiantes | Listado con contrato, programa y avance, terapeuta y próxima sesión. Filtros por sede, estado, profesional y programa; búsqueda por nombre, historia, contrato o representante. Ficha completa y alta | `pacientes` |
| Horarios | Semana de lunes a sábado: resumen por profesional y día, o grilla hora por hora de un profesional; tocar una hora libre abre "Agendar" ya completado | `horarios` |
| Profesionales | Listado con especialidades, sede, horas de trabajo y ocupación de la semana. Ficha con horario y estudiantes que atiende. Alta con especialidades y horario (permiso `personas.profesionales.registrar`) | `profesionales` |
| Solicitudes | Reprogramaciones y cancelaciones pendientes | `solicitudes` |

En la base y en la API se llaman *pacientes*; en la pantalla de Coordinación, *estudiantes*.

**Turnos, como en los horarios que hoy lleva Coordinación** (migración 160):

- El turno lo marca la especialidad principal del profesional (`catalogo.sub_areas.minutos_turno`):
  Neuro cada hora (sesión de 45 minutos y 15 de descanso), Terapia de lenguaje cada 45 minutos
  seguidos. Los turnos se cuentan desde el inicio de la jornada y otra vez después de cada pausa.
- La duración real de la sesión la marca el programa (`duracion_sesion_min`).
- Cupos: terapias grupales hasta 5; Terapia de lenguaje y valoraciones, 1.
- Las valoraciones son de Neuro, pero la coordinación de Estimulación temprana puede agendar,
  como excepción, a sus estudiantes con quienes valoran.
- Cada cita lleva su nota de coordinación ("solo por hoy", "no mover", "rotativo") y se muestra
  con contrato, edad y fase del estudiante.
Cada parte del backend vive en su propio servicio (`backend/lib/modules/coordinacion/`) y todas
filtran con el mismo alcance (`alcance.dart`): las sedes y áreas que coordina el usuario.

### Recorrido del paciente (migración 170)

```
Registro → Valoración inicial → Programa (terapias) → Valoración final → Alta
           1 a 20 sesiones                             1 a 20 sesiones
```

- **Valoraciones** (`agenda.procesos_valoracion`): Coordinación abre la inicial o la final con sus
  sesiones previstas por especialidad (terapia ocupacional, psicología, lenguaje…; parámetro
  `valoracion.sesiones_maximas` = 20), las ajusta y las cierra con su resultado
  (inicial: ingresa a un programa / no requiere; final: alta / continúa / derivado).
- Cada sesión de valoración pertenece a su proceso y a una especialidad prevista: la base no deja
  agendar más de lo previsto, con un profesional de otra especialidad ni en una valoración cerrada.
- El programa empieza cuando se cierra la valoración inicial (si el programa la pide).
- La **etapa** se calcula (`agenda.etapa_paciente`): por valorar, en valoración inicial, listo para
  su programa, en programa, toca valoración final, en valoración final, finalizado o retirado.
- **Línea de tiempo**: todas las sesiones del paciente con su etapa, número ("sesión 3 de 24"),
  terapeuta, asistencia y lo trabajado (resumen de la nota). La ven Coordinación en la ficha del
  estudiante y el terapeuta en la ficha del paciente; el terapeuta abre desde ahí la nota de sus sesiones.
- `catalogo.programa_especialidades`: especialidades que, además de la requerida, pueden atender un
  programa (así las valoraciones las hacen varias especialidades).

**Para probar:** en la pantalla de inicio, el *acceso rápido de desarrollo* lista usuarios de
prueba de cada empresa y rol (solo existe con `APP_ENV=development` y desde la misma PC).

### Herramienta de base de datos (`backend/tool/db.dart`)

| Comando | Qué hace |
|---------|----------|
| `preparar` | Crea la base y el usuario de la API, y aplica migraciones |
| `migrar` | Aplica solo las migraciones pendientes |
| `semilla` | Carga los datos ficticios en una base vacía |
| `reiniciar` | Borra la base y la vuelve a crear con datos ficticios (solo desarrollo) |

Reglas de las migraciones: una migración aplicada **no se edita**; cada cambio es un archivo nuevo
en `backend/db/migrations` con el siguiente número.

Para comprobar las reglas que protege la base (choques de horario, cupos, feriados, etc.):

```bash
psql -U postgres -d ismart_horarios -f backend/db/pruebas/reglas.sql
```

### Datos ficticios

Unas 500 personas (personal, terapeutas, representantes y pacientes) con varios meses de agenda.
Cédulas con prefijo `99` (provincia inexistente) y correos con dominio `.test`, para que ningún dato
coincida con una persona real. **Los programas cargados son de ejemplo** hasta tener la lista real.

### Herramienta de datos (solo desarrollo)

`/api/dev/datos` y la pantalla actual de la app permiten ver, buscar, crear, editar y archivar
registros de cualquier tabla. Solo responde con `APP_ENV=development` y desde la misma PC.
