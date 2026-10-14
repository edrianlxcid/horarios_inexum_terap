/// Configuración de compilación. Se cambia con --dart-define, por ejemplo:
///   flutter run --dart-define=API_URL=http://10.0.2.2:8080   (emulador Android)
class Entorno {
  const Entorno._();

  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');
}
