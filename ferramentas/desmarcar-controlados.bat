@echo off
rem Abre o programa que desmarca Psicotropico/Antimicrobiano no Digifarma.
rem Deixe este arquivo na mesma pasta do desmarcar-controlados.ps1.
rem Se o banco ou a coluna de estoque forem outros, ajuste as duas linhas abaixo.
setlocal
set "BANCO=localhost:C:\Digifarma\Dados\Digifarma6.FDB"
set "ESTOQUE=-Estoque ComEstoque -CampoEstoque PROD_SALDO"
set "PROGRAMA=%~dp0desmarcar-controlados.ps1"

if not exist "%PROGRAMA%" (
  echo Nao achei "%PROGRAMA%".
  echo Coloque este .bat na mesma pasta do desmarcar-controlados.ps1.
  pause
  exit /b 1
)

:menu
cls
echo.
echo   DESMARCAR PSICOTROPICO / ANTIMICROBIANO - DIGIFARMA
echo   Banco: %BANCO%
echo.
echo   1 - Somente VER os controlados com estoque (simulacao, NAO altera nada)
echo   2 - DESMARCAR: na janela, clique nos produtos (Ctrl+clique para varios),
echo       clique OK e depois digite DESMARCAR aqui. Faz backup do banco antes.
echo   3 - Desfazer a ultima vez que desmarcou
echo   4 - Sair
echo.
choice /c 1234 /n /m "  Digite a opcao (1 a 4): "
if errorlevel 4 goto fim
if errorlevel 3 goto desfazer
if errorlevel 2 goto aplicar
goto simular

:simular
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROGRAMA%" -Banco "%BANCO%" %ESTOQUE% -Escolher
goto pausa

:aplicar
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROGRAMA%" -Banco "%BANCO%" %ESTOQUE% -Escolher -Aplicar
goto pausa

:desfazer
set "ULTIMO="
for /f "delims=" %%d in ('dir /b /ad /o-n "%~dp0registros" 2^>nul') do if not defined ULTIMO if exist "%~dp0registros\%%d\desfazer.sql" set "ULTIMO=%~dp0registros\%%d\desfazer.sql"
if not defined ULTIMO (
  echo.
  echo   Nenhuma alteracao para desfazer em "%~dp0registros".
  goto pausa
)
echo.
echo   Vai remarcar o que foi desmarcado nesta execucao:
echo   %ULTIMO%
choice /c SN /m "  Confirma"
if errorlevel 2 goto menu
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROGRAMA%" -Banco "%BANCO%" -Desfazer "%ULTIMO%"
goto pausa

:pausa
echo.
pause
goto menu

:fim
endlocal
