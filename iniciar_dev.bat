@echo off
REM Enciende la API (puerto 8080) y la app web (puerto 5173) en ventanas propias.
REM Si alguno ya está encendido, no lo vuelve a abrir. Para apagarlos, cierra sus ventanas.
cd /d "%~dp0"

set "FLUTTER_BIN=%USERPROFILE%\flutter\bin"
set "PUB_BIN=%LOCALAPPDATA%\Pub\Cache\bin"
set "PATH=%FLUTTER_BIN%;%PUB_BIN%;%PATH%"

if not exist "%PUB_BIN%\dart_frog.bat" (
  echo Instalando Dart Frog CLI...
  call "%FLUTTER_BIN%\dart.bat" pub global activate dart_frog_cli
)
if not exist "%PUB_BIN%\dhttpd.bat" (
  echo Instalando servidor web estatico...
  call "%FLUTTER_BIN%\dart.bat" pub global activate dhttpd
)

netstat -ano | findstr /r /c:":8080 .*LISTENING" >nul
if errorlevel 1 (
  start "iSmart API :8080" /min cmd /k "cd /d "%~dp0backend" && "%PUB_BIN%\dart_frog.bat" dev --port 8080"
) else (
  echo La API ya estaba encendida en el puerto 8080.
)

if not exist "app\build\web\index.html" (
  echo Compilando la app web por primera vez...
  pushd app
  call "%FLUTTER_BIN%\flutter.bat" build web --release
  popd
)

netstat -ano | findstr /r /c:":5173 .*LISTENING" >nul
if errorlevel 1 (
  start "iSmart App :5173" /min cmd /k "cd /d "%~dp0app" && "%PUB_BIN%\dhttpd.bat" --path build/web --host localhost --port 5173"
) else (
  echo La app ya estaba encendida en el puerto 5173.
)

echo.
echo API: http://localhost:8080
echo App: http://localhost:5173  (espera unos segundos a que la API termine de arrancar)
timeout /t 5 >nul
