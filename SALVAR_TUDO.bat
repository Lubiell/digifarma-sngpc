@echo off
chcp 1252 >nul
title SALVAR TUDO - FARMACIA
setlocal enabledelayedexpansion

echo ============================================================
echo  SALVAR TUDO - FARMACIA
echo ============================================================
echo.
echo O repositorio do GitHub foi bloqueado. Este arquivo junta num
echo unico ZIP tudo o que ainda existe desta maquina.
echo.
echo Ele SO COPIA. Nao apaga nada seu, nao altera o Digifarma e
echo nao envia nada para fora.
echo.
echo Pode demorar de 5 a 15 minutos. Deixe a janela aberta.
echo.

set "BASE=%USERPROFILE%\Desktop"
if not exist "%BASE%" set "BASE=C:"
set "DESTINO=%BASE%\SALVAR_FARMACIA"
set "ZIP=%BASE%\SALVAR_FARMACIA.zip"
set "RELATO=%DESTINO%\LEIA-ME.txt"

if exist "%DESTINO%" rmdir /s /q "%DESTINO%" >nul 2>&1
mkdir "%DESTINO%" >nul 2>&1
mkdir "%DESTINO%\agente" >nul 2>&1
mkdir "%DESTINO%\clone" >nul 2>&1
mkdir "%DESTINO%\site" >nul 2>&1
mkdir "%DESTINO%\cache" >nul 2>&1

set "DISCOS="
for %%D in (C D E F G H) do if exist "%%D:\" set "DISCOS=!DISCOS! %%D"
echo Discos que vou varrer:!DISCOS!
echo.

echo ------------------------------------------------------------
echo  1 de 6 - o agente ^(agente_auto.py^)
echo ------------------------------------------------------------
set "N_AGENTE=0"
for %%D in (!DISCOS!) do (
  for /f "delims=" %%A in ('dir /b /s "%%D:\agente_auto.py" 2^>nul') do (
    set /a N_AGENTE+=1
    echo   %%A
    xcopy "%%~dpA*" "%DESTINO%\agente\" /E /I /Y /Q >nul 2>&1
    if exist "%%~dpA..\.git" (
      echo     ^(este tem historico do Git, copiando o clone inteiro^)
      xcopy "%%~dpA..\*" "%DESTINO%\clone\" /E /I /Y /H /Q >nul 2>&1
    )
  )
)
if "%N_AGENTE%"=="0" echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  2 de 6 - os arquivos do site
echo ------------------------------------------------------------
set "N_SITE=0"
for %%D in (!DISCOS!) do (
  for %%N in (balcao.html comum.js app.js) do (
    for /f "delims=" %%A in ('dir /b /s "%%D:\%%N" 2^>nul') do (
      set /a N_SITE+=1
      echo   %%A
      xcopy "%%~dpA*" "%DESTINO%\site\" /E /I /Y /Q >nul 2>&1
    )
  )
)
if "%N_SITE%"=="0" echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  3 de 6 - o aplicativo guardado no navegador
echo ------------------------------------------------------------
echo (o app e um PWA; o navegador guardou uma copia dele)
set "N_CACHE=0"
for %%B in (Google\Chrome Microsoft\Edge BraveSoftware\Brave-Browser) do (
  for %%P in (Default "Profile 1" "Profile 2") do (
    set "ORIG=%LOCALAPPDATA%\%%B\User Data\%%~P\Service Worker\CacheStorage"
    if exist "!ORIG!" (
      set /a N_CACHE+=1
      echo   %%B / %%~P
      xcopy "!ORIG!\*" "%DESTINO%\cache\%%~P\" /E /I /Y /Q >nul 2>&1
    )
  )
)
if "%N_CACHE%"=="0" echo   nada encontrado

echo.
echo ------------------------------------------------------------
echo  4 de 6 - tirando a chave do Firebase da copia
echo ------------------------------------------------------------
echo (chave nao pode viajar num anexo de chat)
set "N_CHAVE=0"
for /f "delims=" %%A in ('dir /b /s "%DESTINO%\*.json" 2^>nul') do (
  findstr /m /c:"PRIVATE KEY" "%%A" >nul 2>&1
  if not errorlevel 1 (
    set /a N_CHAVE+=1
    echo   removido da copia: %%~nxA
    del /f /q "%%A" >nul 2>&1
  )
)
for /f "delims=" %%A in ('dir /b /s "%DESTINO%\*.*" 2^>nul') do (
  echo %%~nxA| findstr /i /c:"adminsdk" /c:"serviceaccount" /c:"service-account" >nul 2>&1
  if not errorlevel 1 (
    if exist "%%A" (
      set /a N_CHAVE+=1
      echo   removido da copia: %%~nxA
      del /f /q "%%A" >nul 2>&1
    )
  )
)
if "%N_CHAVE%"=="0" echo   nenhuma chave encontrada na copia

echo.
echo ------------------------------------------------------------
echo  5 de 6 - anotando o que foi achado
echo ------------------------------------------------------------
echo SALVAR_FARMACIA - gerado em %DATE% %TIME% > "%RELATO%"
echo. >> "%RELATO%"
echo maquina ........... %COMPUTERNAME% >> "%RELATO%"
echo copias do agente .. %N_AGENTE% >> "%RELATO%"
echo arquivos de site .. %N_SITE% >> "%RELATO%"
echo caches de navegador %N_CACHE% >> "%RELATO%"
echo chaves removidas .. %N_CHAVE% >> "%RELATO%"
echo. >> "%RELATO%"
echo === arvore do que foi copiado === >> "%RELATO%"
dir /b /s "%DESTINO%\agente" >> "%RELATO%" 2>nul
dir /b /s "%DESTINO%\site" >> "%RELATO%" 2>nul
dir /b "%DESTINO%\clone" >> "%RELATO%" 2>nul
echo   anotado em LEIA-ME.txt

echo.
echo ------------------------------------------------------------
echo  6 de 6 - fechando o ZIP
echo ------------------------------------------------------------
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
pushd "%BASE%"
tar -a -c -f "%ZIP%" SALVAR_FARMACIA >nul 2>&1
popd
if not exist "%ZIP%" goto SEM_TAR
for %%Z in ("%ZIP%") do set /a MB=%%~zZ/1048576
echo   ZIP fechado: %MB% MB
echo.
echo ============================================================
echo  PRONTO
echo ============================================================
echo.
echo Anexe este arquivo no chat:
echo.
echo    %ZIP%
echo.
if %MB% GEQ 30 echo ATENCAO: %MB% MB pode ser grande para anexar. Se o chat
if %MB% GEQ 30 echo recusar, apague a pasta cache de dentro do ZIP e tente de novo.
echo.
echo O agente continua rodando normalmente. Nao apague a pasta dele.
goto FIM

:SEM_TAR
echo   nao consegui fechar o ZIP ^(o comando tar nao existe nesta
echo   versao do Windows^).
echo.
echo   A pasta com tudo copiado ficou aqui:
echo     %DESTINO%
echo   Clique com o botao direito nela, Enviar para, Pasta compactada,
echo   e anexe o ZIP no chat.

:FIM
echo.
echo ============================================================
pause
