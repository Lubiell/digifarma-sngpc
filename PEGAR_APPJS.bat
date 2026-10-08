@echo off
chcp 1252 >nul
title PEGAR O APP.JS DO CACHE DO NAVEGADOR
setlocal enabledelayedexpansion

echo ============================================================
echo  PEGAR O APP.JS
echo ============================================================
echo.
echo O pacote anterior trouxe a casca do app, mas o app.js do
echo projeto foi sobrescrito pelo app.js do proprio Windows
echo durante a copia. Culpa do meu arquivo, nao sua.
echo.
echo Este aqui pega SO o cache do navegador, onde o aplicativo
echo ficou guardado, e nao mistura pasta nenhuma.
echo.
echo Ele SO COPIA. Nao apaga nada seu.
echo.

set "BASE=%USERPROFILE%\Desktop"
if not exist "%BASE%" set "BASE=C:"
set "DESTINO=%BASE%\PEGAR_APPJS"
set "ZIP=%BASE%\PEGAR_APPJS.zip"

if exist "%DESTINO%" rmdir /s /q "%DESTINO%" >nul 2>&1
mkdir "%DESTINO%" >nul 2>&1

echo ------------------------------------------------------------
echo  1 de 3 - cache dos navegadores
echo ------------------------------------------------------------
set "N=0"
for %%B in ("Google\Chrome" "Microsoft\Edge" "BraveSoftware\Brave-Browser") do (
  for %%P in ("Default" "Profile 1" "Profile 2" "Profile 3") do (
    set "SW=%LOCALAPPDATA%\%%~B\User Data\%%~P\Service Worker\CacheStorage"
    if exist "!SW!" (
      set /a N+=1
      echo   sw    %%~B / %%~P
      robocopy "!SW!" "%DESTINO%\sw-!N!" /E /NFL /NDL /NJH /NJS /NP >nul 2>&1
    )
    set "CC=%LOCALAPPDATA%\%%~B\User Data\%%~P\Cache\Cache_Data"
    if exist "!CC!" (
      set /a N+=1
      echo   cache %%~B / %%~P
      robocopy "!CC!" "%DESTINO%\cache-!N!" /E /NFL /NDL /NJH /NJS /NP >nul 2>&1
    )
  )
)
if "%N%"=="0" echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  2 de 3 - procurando app.js que seja do projeto
echo ------------------------------------------------------------
echo ^(o do Windows comeca com Copyright Microsoft; o nosso cita
echo  farmacia/inventario. Procuro pelo nosso, sem copiar pasta.^)
set "ACHOU=0"
for %%D in (C D E F G H) do (
  if exist "%%D:\" (
    for /f "delims=" %%A in ('dir /b /s "%%D:\app.js" 2^>nul') do (
      findstr /m /c:"farmacia/inventario" /c:"MOTIVO_SALDO" "%%A" >nul 2>&1
      if not errorlevel 1 (
        set /a ACHOU+=1
        echo   ACHEI  %%A
        copy /y "%%A" "%DESTINO%\app-achado-!ACHOU!.js" >nul 2>&1
      )
    )
  )
)
if "%ACHOU%"=="0" echo   nenhum app.js do projeto solto no disco

echo.
echo ------------------------------------------------------------
echo  3 de 3 - fechando o ZIP
echo ------------------------------------------------------------
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
pushd "%BASE%"
tar -a -c -f "%ZIP%" PEGAR_APPJS >nul 2>&1
popd
if not exist "%ZIP%" goto SEM_TAR
for %%Z in ("%ZIP%") do set /a MB=%%~zZ/1048576
echo   ZIP fechado: %MB% MB
echo.
echo ============================================================
echo  PRONTO
echo ============================================================
echo.
echo Anexe no chat:
echo.
echo    %ZIP%
echo.
if %MB% GEQ 40 echo ATENCAO: %MB% MB. Se o chat recusar, apague as pastas
if %MB% GEQ 40 echo cache-* de dentro do ZIP e deixe so as sw-*.
echo.
echo IMPORTANTE: antes de rodar, abra o app uma vez no navegador
echo deste computador. Mesmo dando erro, o navegador reescreve o
echo cache e o app.js aparece aqui.
goto FIM

:SEM_TAR
echo   nao consegui fechar o ZIP ^(tar nao existe nesta versao do
echo   Windows^). A pasta ficou aqui:
echo     %DESTINO%
echo   Compacte com o botao direito e anexe no chat.

:FIM
echo.
echo ============================================================
pause
