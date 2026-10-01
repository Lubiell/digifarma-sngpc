@echo off
chcp 1252 >nul
title BACKUP DO AGENTE - FARMACIA
echo ============================================================
echo  BACKUP DO AGENTE (o GitHub do projeto saiu do ar)
echo ============================================================
echo.
echo Este arquivo so COPIA. Ele nao apaga e nao muda nada.
echo.

set "DESTINO=%USERPROFILE%\Desktop\BACKUP_FARMACIA"
if not exist "%DESTINO%" mkdir "%DESTINO%" >nul 2>&1
if not exist "%DESTINO%" set "DESTINO=C:\BACKUP_FARMACIA"
if not exist "%DESTINO%" mkdir "%DESTINO%" >nul 2>&1

echo Destino: %DESTINO%
echo.
echo Procurando o agente no disco C: ...
echo (pode levar alguns minutos, deixe terminar)
echo.

set "ACHOU="
for /f "delims=" %%A in ('dir /b /s "C:\agente_auto.py" 2^>nul') do (
  set "ACHOU=1"
  echo Encontrado: %%A
  for %%P in ("%%~dpA.") do (
    echo   copiando a pasta %%~nxP ...
    xcopy "%%~dpA*" "%DESTINO%\%%~nxP\" /E /I /Y /Q >nul 2>&1
  )
)

echo.
if not defined ACHOU (
  echo NAO ENCONTREI agente_auto.py no disco C:.
  echo Se o agente estiver em outro disco, me diga a letra.
) else (
  echo Copia feita. Confira a pasta:
  echo   %DESTINO%
  echo.
  echo Guarde esta pasta. Hoje ela e a unica copia conhecida do agente.
)

echo.
echo ============================================================
pause
