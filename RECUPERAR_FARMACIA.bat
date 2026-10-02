@echo off
chcp 1252 >nul
title RECUPERAR FARMACIA - juntar tudo num ZIP
setlocal enabledelayedexpansion

echo ============================================================
echo  RECUPERAR FARMACIA
echo ============================================================
echo.
echo O repositorio do GitHub foi bloqueado. Este arquivo junta num
echo unico ZIP tudo o que ainda existe desta maquina, para voce
echo anexar no chat.
echo.
echo Ele SO COPIA. Nao apaga, nao altera e nao envia nada.
echo.

set "BASE=%USERPROFILE%\Desktop"
if not exist "%BASE%" set "BASE=C:\"
set "DESTINO=%BASE%\RECUPERAR_FARMACIA"
set "ZIP=%BASE%\RECUPERAR_FARMACIA.zip"

if exist "%DESTINO%" rmdir /s /q "%DESTINO%" >nul 2>&1
mkdir "%DESTINO%" >nul 2>&1
mkdir "%DESTINO%\agente" >nul 2>&1
mkdir "%DESTINO%\site" >nul 2>&1
mkdir "%DESTINO%\cache" >nul 2>&1

echo ------------------------------------------------------------
echo  1 de 4 - procurando o agente no disco C:
echo ------------------------------------------------------------
echo (demora alguns minutos, deixe terminar)
set "ACHEI_AGENTE="
for /f "delims=" %%A in ('dir /b /s "C:\agente_auto.py" 2^>nul') do (
  set "ACHEI_AGENTE=1"
  echo   %%A
  xcopy "%%~dpA*" "%DESTINO%\agente\" /E /I /Y /Q >nul 2>&1
)
if not defined ACHEI_AGENTE echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  2 de 4 - procurando os arquivos do site
echo ------------------------------------------------------------
set "ACHEI_SITE="
for %%N in (app.js comum.js balcao.html index.html) do (
  for /f "delims=" %%A in ('dir /b /s "C:\%%N" 2^>nul') do (
    set "ACHEI_SITE=1"
    echo   %%A
    xcopy "%%~dpA*" "%DESTINO%\site\" /E /I /Y /Q >nul 2>&1
  )
)
if not defined ACHEI_SITE echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  3 de 4 - copiando o cache do navegador
echo ------------------------------------------------------------
echo (o aplicativo ficou guardado no navegador; da para tirar dali)
set "CR=%LOCALAPPDATA%\Google\Chrome\User Data"
set "ED=%LOCALAPPDATA%\Microsoft\Edge\User Data"
set "ACHEI_CACHE="
for %%P in (Default Profile 1 Profile 2) do (
  if exist "%CR%\%%P\Service Worker\CacheStorage" (
    set "ACHEI_CACHE=1"
    echo   Chrome %%P
    xcopy "%CR%\%%P\Service Worker\CacheStorage\*" "%DESTINO%\cache\chrome-%%P\" /E /I /Y /Q >nul 2>&1
  )
  if exist "%ED%\%%P\Service Worker\CacheStorage" (
    set "ACHEI_CACHE=1"
    echo   Edge %%P
    xcopy "%ED%\%%P\Service Worker\CacheStorage\*" "%DESTINO%\cache\edge-%%P\" /E /I /Y /Q >nul 2>&1
  )
)
if not defined ACHEI_CACHE echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  4 de 4 - fechando o ZIP
echo ------------------------------------------------------------
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
tar -a -c -f "%ZIP%" -C "%BASE%" RECUPERAR_FARMACIA >nul 2>&1

if not exist "%ZIP%" goto SEM_ZIP
for %%Z in ("%ZIP%") do set "TAM=%%~zZ"
echo   ZIP criado: %TAM% bytes
echo.
echo ============================================================
echo  PRONTO
echo ============================================================
echo.
echo Anexe este arquivo no chat:
echo.
echo   %ZIP%
echo.
echo Se ficar grande demais para anexar, me avise o tamanho que
echo eu te digo o que tirar.
goto FIM

:SEM_ZIP
echo   NAO consegui fechar o ZIP ^(o comando tar pode nao existir
echo   nesta versao do Windows^).
echo.
echo   A pasta com tudo copiado ficou aqui:
echo     %DESTINO%
echo   Compacte ela com o botao direito e anexe no chat.

:FIM
echo.
echo ============================================================
pause
