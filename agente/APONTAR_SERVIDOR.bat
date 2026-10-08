@echo off
chcp 1252 >nul
title APONTAR O SERVIDOR PARA O REPOSITORIO NOVO
setlocal enabledelayedexpansion

set "CRU=https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/agente"

echo ============================================================
echo  APONTAR O SERVIDOR PARA O REPOSITORIO NOVO
echo ============================================================
echo.
echo A conta antiga do GitHub foi bloqueada. Todo .bat desta pasta
echo ainda baixa do endereco velho, que responde 404 - inclusive o
echo ATUALIZAR_AGENTE, que por isso nao consegue se consertar.
echo.
echo Este arquivo troca os .bat pelos novos e depois chama o
echo ATUALIZAR_AGENTE, que baixa o agente e os dois arquivos que
echo o acompanham.
echo.
echo Endereco novo:
echo   %CRU%
echo.

if not exist "agente_auto.py" goto PASTA_ERRADA

echo ------------------------------------------------------------
echo  1 de 2 - trocando os .bat
echo ------------------------------------------------------------
set "TROCADOS=0"
set "MANTIDOS=0"
for %%N in (ATUALIZAR_AGENTE.bat SERVIDOR_AGORA.bat CONSERTAR_TUDO.bat LIMPAR.bat DIAGNOSTICO_ANVISA.bat TROCAR_CHAVE_FIREBASE.bat INSTALAR_AGENTE.bat AGENDAR_ANVISA.bat) do call :TROCAR "%%N"

echo.
echo   trocados: !TROCADOS!   mantidos como estavam: !MANTIDOS!
echo   os antigos ficaram com a extensao .antigo nesta pasta
echo.

if "!TROCADOS!"=="0" goto NADA_TROCADO

echo ------------------------------------------------------------
echo  2 de 2 - chamando o ATUALIZAR_AGENTE
echo ------------------------------------------------------------
echo (ele vai baixar agente_auto.py, mapa_xml.py e teste_agente.py)
echo.
call ATUALIZAR_AGENTE.bat
goto FIM

:TROCAR
REM  %1 nome do .bat. Baixa, confere e so entao troca. Falha aqui
REM  mantem o arquivo que estava, com aviso, e segue para o proximo.
curl -fsSL -o "%~1.novo" "%CRU%/%~1"
if errorlevel 1 (
  echo   AVISO  %~1 nao baixou, mantido o que estava
  if exist "%~1.novo" del "%~1.novo" >nul 2>&1
  set /a MANTIDOS+=1
  goto :eof
)
findstr /i /c:"@echo off" "%~1.novo" >nul 2>&1
if errorlevel 1 (
  echo   AVISO  %~1 baixado nao parece um .bat, mantido o que estava
  del "%~1.novo" >nul 2>&1
  set /a MANTIDOS+=1
  goto :eof
)
findstr /c:"digifarma-sngpc" "%~1.novo" >nul 2>&1
if errorlevel 1 echo   nota   %~1 nao cita o repositorio novo ^(pode ser normal^)
if exist "%~1" move /y "%~1" "%~1.antigo" >nul 2>&1
move /y "%~1.novo" "%~1" >nul
echo   ok     %~1
set /a TROCADOS+=1
goto :eof

:PASTA_ERRADA
echo ------------------------------------------------------------
echo  PARE
echo ------------------------------------------------------------
echo.
echo Nao achei o agente_auto.py nesta pasta, entao este nao e o
echo lugar certo. Nada foi alterado.
echo.
echo Copie este arquivo para a pasta do agente e rode de novo.
goto FIM

:NADA_TROCADO
echo ------------------------------------------------------------
echo  PARE
echo ------------------------------------------------------------
echo.
echo Nenhum .bat foi baixado, entao nao chamei o ATUALIZAR_AGENTE.
echo Nada foi alterado: os arquivos que estavam continuam no lugar.
echo.
echo Quase sempre e internet ou firewall barrando o github.com.
echo Teste assim e me mande o que aparecer:
echo.
echo   curl -fsSL -o teste.txt %CRU%/ATUALIZAR_AGENTE.bat
echo.

:FIM
echo.
echo ============================================================
pause
