# Centro de Psicología – Horarios y Terapias

Aplicación multiplataforma para la gestión de un centro de psicología.

## Arquitectura

| Capa | Tecnología | Carpeta |
|------|------------|---------|
| App (Android, iOS, Web, macOS) | Flutter / Dart | `app/` |
| API REST | Dart Frog (Dart) | `backend/` |
| Base de datos | PostgreSQL 17 | local |

La app **nunca** se conecta directamente a la base de datos: todo pasa por la API (`backend/`),
que es la que valida permisos y protege los datos clínicos de los pacientes.

## Requisitos

- Flutter SDK (stable) – incluye Dart
- Android Studio (SDK de Android + emulador)
- PostgreSQL 17
- Dart Frog CLI: `dart pub global activate dart_frog_cli`
- iOS / macOS: requiere una Mac con Xcode

## Puesta en marcha

```bash
cp .env.example .env        # completar la contraseña de la BD
cd backend && dart_frog dev # API en http://localhost:8080
cd app && flutter run       # app
```

### Paquetes base
- **app:** dio (HTTP), go_router (navegación), flutter_riverpod (estado), flutter_secure_storage (tokens), intl (fechas)
- **backend:** dart_frog, postgres, dotenv
