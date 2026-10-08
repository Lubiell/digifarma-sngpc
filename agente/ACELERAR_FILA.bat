@echo off
chcp 1252 >nul
title ACELERAR A FILA DO AGENTE
setlocal

echo ============================================================
echo  ACELERAR A FILA DO AGENTE
echo ============================================================
echo.
echo A tarefa AgenteSNGPC_Fila roda de 5 em 5 minutos. E esse o
echo tempo entre apertar um botao no app e o agente atender.
echo.
echo Este arquivo troca para 1 em 1 minuto. A fila so le um no do
echo Firebase e sai quando nao ha pedido, entao o custo e uma
echo leitura por minuto.
echo.
echo Precisa de ADMINISTRADOR: a tarefa roda como SYSTEM.
echo.

net session >nul 2>&1
if errorlevel 1 goto SEM_ADMIN

if exist "%~dp0agente_auto.py" goto TEM_PASTA
echo  Este arquivo precisa estar na pasta do agente, junto do
echo  agente_auto.py. Nada foi alterado.
goto FIM

:TEM_PASTA
echo ------------------------------------------------------------
echo  como esta hoje
echo ------------------------------------------------------------
schtasks /Query /TN "AgenteSNGPC_Fila" >nul 2>&1
if errorlevel 1 goto SEM_TAREFA
schtasks /Query /TN "AgenteSNGPC_Fila" /FO LIST | findstr /i /c:"Repetir" /c:"Repeat" /c:"Agendar" /c:"Schedule"
echo.

set "PYEXE="
for /f "delims=" %%P in ('where py 2^>nul') do if not defined PYEXE set "PYEXE=%%P"
if not defined PYEXE for /f "delims=" %%P in ('where python 2^>nul') do if not defined PYEXE set "PYEXE=%%P"
if not defined PYEXE goto SEM_PYTHON

echo ------------------------------------------------------------
echo  trocando para 1 minuto
echo ------------------------------------------------------------
schtasks /Create /TN "AgenteSNGPC_Fila" /SC MINUTE /MO 1 /RL HIGHEST /RU SYSTEM /F ^
  /TR "\"%PYEXE%\" \"%~dp0agente_auto.py\" --fila" >nul
if errorlevel 1 goto FALHOU

echo   pronto. Como ficou:
schtasks /Query /TN "AgenteSNGPC_Fila" /FO LIST | findstr /i /c:"Repetir" /c:"Repeat" /c:"Agendar" /c:"Schedule"
echo.
echo   Agora o app responde em ate um minuto.
goto FIM

:SEM_ADMIN
echo  PARE: rode como ADMINISTRADOR. Clique com o botao direito
echo  neste arquivo e escolha "Executar como administrador".
echo  Nada foi alterado.
goto FIM

:SEM_TAREFA
echo  Nao existe a tarefa AgenteSNGPC_Fila nesta maquina. O agente
echo  nunca foi instalado aqui, ou foi instalado com outro nome.
echo  Rode o INSTALAR_AGENTE.bat. Nada foi alterado.
goto FIM

:SEM_PYTHON
echo  Python nao encontrado. Nada foi alterado.
goto FIM

:FALHOU
echo  Nao consegui recriar a tarefa. A anterior pode ter sido
echo  removida: confira com
echo    schtasks /Query /TN "AgenteSNGPC_Fila"
echo  e, se nao existir, rode o INSTALAR_AGENTE.bat.

:FIM
echo.
echo ============================================================
pause
