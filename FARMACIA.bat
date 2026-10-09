@echo off
chcp 1252 >nul
title FARMACIA - SNGPC
setlocal enabledelayedexpansion

set "CRU=https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main"

REM  Um arquivo so no servidor. Cada ferramenta e baixada na hora, usada
REM  e apagada: o que mora aqui e o agente, a configuracao e a chave.
REM  Antes eram doze .bat espalhados, e manter doze copias em dia numa
REM  maquina onde ninguem vai era o que fazia o servidor ficar para tras.
set "TMPD=%TEMP%\farmacia_sngpc"
if not exist "%TMPD%" mkdir "%TMPD%" >nul 2>&1

:MENU
cls
echo ============================================================
echo  FARMACIA - SNGPC
echo ============================================================
echo.
echo  Pasta do agente: %~dp0
echo.
echo   1 - Consertar tudo ^(uma visita, tudo de uma vez^)
echo   2 - Atualizar o agente agora
echo   3 - Rodar o servidor agora ^(sincronizar e colher respostas^)
echo   4 - Instalar a chave nova do Firebase
echo   5 - Acelerar a fila ^(precisa de administrador^)
echo   6 - Diagnostico do Anvisa.exe
echo   7 - Limpar as sobras desta pasta
echo   8 - Desmarcar psicotropico/antimicrobiano no Digifarma
echo   9 - Instalar o agente nesta maquina
echo   R - Acesso remoto: testar e ligar SSH/RDP ^(administrador^)
echo   0 - Sair
echo.
choice /c 1234567890R /n /m "  Opcao: "
set "OP=%ERRORLEVEL%"
if "%OP%"=="10" goto FIM
if "%OP%"=="1" call :RODAR CONSERTAR_TUDO.bat agente
if "%OP%"=="2" call :RODAR ATUALIZAR_AGENTE.bat agente
if "%OP%"=="3" call :RODAR SERVIDOR_AGORA.bat agente
if "%OP%"=="4" call :RODAR INSTALAR_CHAVE.bat agente
if "%OP%"=="5" call :RODAR ACELERAR_FILA.bat agente
if "%OP%"=="6" call :RODAR DIAGNOSTICO_ANVISA.bat agente
if "%OP%"=="7" call :RODAR LIMPAR.bat agente
if "%OP%"=="8" call :DESMARCAR
if "%OP%"=="9" call :RODAR INSTALAR_AGENTE.bat agente
if "%OP%"=="11" call :RODAR ACESSO_REMOTO.bat agente
echo.
pause
goto MENU

REM ------------------------------------------------------------
REM  %1 nome do arquivo   %2 pasta dele no repositorio
REM  Baixa para a pasta do agente, roda e apaga. Fica so o que o
REM  proprio programa gravar.
REM ------------------------------------------------------------
:RODAR
echo.
echo  baixando %~1 ...
curl -fsSL -o "%~dp0%~1" "%CRU%/%~2/%~1"
if errorlevel 1 goto SEM_REDE
findstr /i /c:"@echo off" "%~dp0%~1" >nul 2>&1
if errorlevel 1 goto VEIO_QUEBRADO
echo  ok
echo.
call "%~dp0%~1"
del "%~dp0%~1" >nul 2>&1
goto :eof

REM ------------------------------------------------------------
REM  O desmarcar sao dois arquivos e grava no Digifarma: baixa os
REM  dois, roda, e apaga os dois no fim.
REM ------------------------------------------------------------
:DESMARCAR
echo.
echo  ATENCAO: isto GRAVA no Digifarma. Produto ja transmitido ao
echo  SNGPC como controlado, se desmarcado, gera divergencia na
echo  ANVISA. O programa simula primeiro e faz backup antes de
echo  alterar.
echo.
choice /c SN /n /m "  Continuar [S/N]? "
if errorlevel 2 goto :eof
echo.
echo  baixando as duas pecas ...
curl -fsSL -o "%TMPD%\desmarcar-controlados.ps1" "%CRU%/ferramentas/desmarcar-controlados.ps1"
if errorlevel 1 goto SEM_REDE
curl -fsSL -o "%TMPD%\desmarcar-controlados.bat" "%CRU%/ferramentas/desmarcar-controlados.bat"
if errorlevel 1 goto SEM_REDE
echo  ok
echo.
call "%TMPD%\desmarcar-controlados.bat"
del "%TMPD%\desmarcar-controlados.ps1" >nul 2>&1
del "%TMPD%\desmarcar-controlados.bat" >nul 2>&1
goto :eof

:SEM_REDE
echo.
echo  Nao consegui baixar. Quase sempre e internet ou firewall
echo  barrando o github.com. Nada foi alterado.
goto :eof

:VEIO_QUEBRADO
echo.
echo  O arquivo baixado veio incompleto. Nada foi alterado.
del "%~dp0%~1" >nul 2>&1
goto :eof

:FIM
rmdir /s /q "%TMPD%" >nul 2>&1
endlocal
