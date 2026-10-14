@echo off
REM Enciende la API (puerto 8080) y la app web (puerto 5173) en ventanas propias.
REM Para apagarlas, cierra esas ventanas.
set PATH=%PATH%;%USERPROFILE%\flutter\bin;%LOCALAPPDATA%\Pub\Cache\bin
cd /d "%~dp0"

start "iSmart API :8080" /min cmd /k "cd backend && dart_frog dev --port 8080"

if not exist "app\build\web\index.html" (
  echo Compilando la app web por primera vez...
  pushd app
  call flutter build web --release
  popd
)
start "iSmart App :5173" /min cmd /k "cd app && dhttpd --path build/web --host localhost --port 5173"

echo.
echo API: http://localhost:8080
echo App: http://localhost:5173  (espera unos segundos a que la API termine de arrancar)
