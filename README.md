# iSmart Salud – Sistema de horarios

Aplicación multiplataforma para la gestión de agenda, pacientes y terapias de iSmart Salud
(áreas Neuro/Tomatis e Inglés/Estimulación, varias sedes).

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
