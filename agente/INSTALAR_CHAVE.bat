@echo off
chcp 1252 >nul
title INSTALAR A CHAVE NOVA DO FIREBASE
setlocal

set "CRU=https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/agente"

echo ============================================================
echo  INSTALAR A CHAVE NOVA DO FIREBASE
echo ============================================================
echo.
echo O TROCAR_CHAVE_FIREBASE.bat exige a chave ATUAL para descobrir
echo qual conta trocar. Quando a chave atual ja foi apagada no
echo console - que e justamente a hora em que mais se precisa
echo instalar a nova - ele para dizendo que nao achou.
echo.
echo A conta e o projeto estao dentro do proprio JSON novo. Este
echo arquivo usa isso: nao precisa da chave velha.
echo.
echo Ele procura a chave baixada em Downloads, na Area de Trabalho
echo e nesta pasta, e guarda a que estiver no lugar antes de trocar.
echo.

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY goto SEM_PYTHON

if exist "%~dp0agente_auto.py" goto TEM_PASTA
echo  Este arquivo precisa estar na pasta do agente, junto do
echo  agente_auto.py. Nada foi alterado.
goto FIM

:TEM_PASTA
echo ------------------------------------------------------------
echo  baixando o instalador
echo ------------------------------------------------------------
curl -fsSL -o "%~dp0instalar_chave.py" "%CRU%/instalar_chave.py"
if errorlevel 1 goto SEM_REDE
%PY% -c "import sys;t=open(sys.argv[1],encoding='utf-8').read();sys.exit(0 if 'def principal(' in t and compile(t,'a','exec') is not None else 1)" "%~dp0instalar_chave.py"
if errorlevel 1 goto VEIO_QUEBRADO
echo   ok
echo.

echo ------------------------------------------------------------
echo  instalando
echo ------------------------------------------------------------
%PY% "%~dp0instalar_chave.py" %1
goto FIM

:SEM_PYTHON
echo  Python nao encontrado nesta maquina. Sem ele nao da para ler
echo  o JSON com seguranca. Nada foi alterado.
goto FIM

:SEM_REDE
echo  Nao consegui baixar o instalador. Quase sempre e internet ou
echo  firewall barrando o github.com. Nada foi alterado.
goto FIM

:VEIO_QUEBRADO
echo  O instalador baixado veio incompleto. Nada foi alterado.
del "%~dp0instalar_chave.py" >nul 2>&1

:FIM
echo.
echo ============================================================
pause
