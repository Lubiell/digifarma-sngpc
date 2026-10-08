@echo off
chcp 1252 >nul
title ACHAR O APP.JS
setlocal

set "CRU=https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main"

echo ============================================================
echo  ACHAR O APP.JS
echo ============================================================
echo.
echo O cache inteiro deu 654 MB e nao cabe no chat. Entao, em vez
echo de mandar o cache, este programa abre o cache AQUI e tira so
echo o app.js de dentro dele.
echo.
echo O resultado sao um ou dois arquivos de alguns KB na area de
echo trabalho, esses sim do tamanho de anexar.
echo.
echo Ele SO LE o cache. Nao apaga nada e nao mexe no navegador.
echo.
echo Pode apagar o PEGAR_APPJS.zip de 654 MB, nao serve mais.
echo.

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY goto SEM_PYTHON

echo ------------------------------------------------------------
echo  1 de 2 - baixando o programa
echo ------------------------------------------------------------
curl -fsSL -o "%TEMP%\ACHAR_APPJS.py" "%CRU%/ACHAR_APPJS.py"
if errorlevel 1 goto SEM_REDE
%PY% -c "import sys;t=open(sys.argv[1],encoding='utf-8').read();sys.exit(0 if 'def procurar(' in t and compile(t,'a','exec') is not None else 1)" "%TEMP%\ACHAR_APPJS.py"
if errorlevel 1 goto VEIO_QUEBRADO
echo   ok

echo.
echo ------------------------------------------------------------
echo  2 de 2 - abrindo o cache
echo ------------------------------------------------------------
echo (le arquivo por arquivo; pode levar varios minutos)
echo.
%PY% "%TEMP%\ACHAR_APPJS.py"
set "RESULTADO=%ERRORLEVEL%"
del "%TEMP%\ACHAR_APPJS.py" >nul 2>&1
if not "%RESULTADO%"=="0" goto NAO_ACHOU
goto FIM

:SEM_PYTHON
echo  Python nao encontrado nesta maquina, e e ele que faz o
echo  trabalho. Rode este arquivo na mesma maquina onde o agente
echo  roda, ou instale o Python e tente de novo.
goto FIM

:SEM_REDE
echo  Nao consegui baixar o programa. Quase sempre e internet ou
echo  firewall barrando o github.com. Nada foi alterado.
goto FIM

:VEIO_QUEBRADO
echo  O programa baixado veio incompleto. Nada foi alterado.
del "%TEMP%\ACHAR_APPJS.py" >nul 2>&1
goto FIM

:NAO_ACHOU
echo.
echo  Nao achei o app.js no cache. O que costuma resolver: abrir o
echo  app uma vez no Chrome deste computador, no perfil onde o
echo  atalho da farmacia esta ^(Profile 2^), mesmo que de erro de
echo  pagina. O navegador reescreve o cache e ai sim aparece.

:FIM
echo.
echo ============================================================
pause
