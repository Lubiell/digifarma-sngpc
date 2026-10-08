@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Agente SNGPC - limpeza

REM ============================================================
REM  LIMPAR.bat
REM  Tira da pasta o que o proprio agente foi deixando: backups
REM  antigos, logs de dias que ja passaram, listas geradas.
REM
REM  Dois cliques ......... mostra o que sairia e pergunta
REM  LIMPAR.bat /simular .. so mostra, nunca apaga
REM  LIMPAR.bat /auto ..... apaga sem perguntar, para agendar
REM
REM  O QUE ELE NUNCA APAGA
REM  Ha uma lista branca conferida arquivo por arquivo, e a
REM  pasta do XML fica inteira de fora: o sngpc_AAAA-MM-DD.xml
REM  de cada envio e historico de transmissao, nao e log.
REM
REM  De cada tipo ficam os mais recentes. Backup e log so
REM  servem para voltar atras, e voltar atras seis versoes nao
REM  acontece - mas voltar uma acontece toda semana.
REM
REM  Nao precisa de administrador. So mexe nesta pasta.
REM ============================================================

cd /d "%~dp0"

set "MODO=perguntar"
if /i "%~1"=="/simular" set "MODO=simular"
if /i "%~1"=="/auto" set "MODO=auto"

set "TOTAL=0"
set "BYTES=0"
set "LISTA=%TEMP%\limpar_sngpc_%RANDOM%.txt"
if exist "%LISTA%" del "%LISTA%" >nul 2>&1

echo.
echo  ============================================================
echo   LIMPEZA DA PASTA DO AGENTE
echo  ============================================================
echo   %~dp0
echo.
echo   Ficam sempre: o agente, a configuracao, as chaves, as regras,
echo   os .bat, os .rar, a pasta do XML inteira e os ajustes_*.json,
echo   que sao o registro de tudo que foi escrito no Digifarma.
echo  ============================================================
echo.

REM  padrao                              quantos ficam   o que e
call :ACHAR "agente_auto_antes_de_*.py"        3  "backup do agente"
call :ACHAR "atualizacao_*.log"                5  "log de atualizacao"
call :ACHAR "servidor_agora_*.log"             5  "log do SERVIDOR_AGORA"
call :ACHAR "limpeza_*.log"                    3  "log desta limpeza"
call :ACHAR "tarefas_saldo_*.txt"              3  "folha de conferencia"
call :ACHAR "negativos_*.txt"                  3  "lista de negativos"
call :ACHAR "comparacao_*.html"                3  "folha de comparacao"
call :ACHAR "RESPOSTAS_DO_SERVIDOR_*.txt"      3  "respostas do servidor"
call :ACHAR "diagnostico_anvisa*.txt"          2  "diagnostico do Anvisa"
call :ACHAR "agente_auto_novo.py"              0  "download interrompido"
call :ACHAR "*.tmp"                            0  "temporario"
REM  sobra do __pycache__ que escapou da pasta, com nome de versao
call :ACHAR "*.cpython-*.py"                   0  "sobra do cache do Python"
call :ACHAR "*.pyc"                            0  "bytecode do Python"

REM  o __pycache__ e regerado sozinho na proxima execucao
if exist "%~dp0__pycache__" (
  echo   __pycache__\                              cache do Python
  set /a TOTAL+=1
  echo PASTA:__pycache__>> "%LISTA%"
)

echo.
if "%TOTAL%"=="0" (
  echo   Nada a limpar. A pasta ja esta enxuta.
  echo.
  if not "%MODO%"=="auto" pause
  goto :FIM
)

set /a MB=%BYTES%/1048576
echo  ============================================================
echo   %TOTAL% item^(ns^), cerca de %MB% MB
echo  ============================================================
echo.

if "%MODO%"=="simular" (
  echo   Modo simulacao: nada foi apagado.
  echo   Rode sem /simular para apagar de verdade.
  echo.
  pause
  goto :FIM
)

if "%MODO%"=="perguntar" (
  set /p RESP=  Apagar estes arquivos [S/N]: 
  if /i not "!RESP!"=="S" (
    echo.
    echo   Nada foi apagado.
    echo.
    pause
    goto :FIM
  )
)

set "LOG=%~dp0limpeza_%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%.log"
echo ==== %DATE% %TIME% ==== >> "%LOG%"

echo.
for /f "usebackq delims=" %%L in ("%LISTA%") do call :APAGAR "%%L"

echo.
echo   Pronto. O que foi apagado esta em:
echo   %LOG%
echo.
if not "%MODO%"=="auto" pause
goto :FIM

REM ============================================================
REM  ACHAR - lista o que passa do limite, sem apagar nada ainda
REM    %1 padrao   %2 quantos ficam   %3 descricao
REM
REM  O skip do for pula os mais NOVOS: o /o-d ordena do mais
REM  recente para o mais antigo, entao o que sobra e o velho.
REM ============================================================
:ACHAR
REM  skip=0 nao existe: o for /f exige 1 ou mais e aborta com
REM  "delims=" foi inesperado neste momento". Guardar zero arquivos e
REM  justamente o caso de *.tmp, *.pyc e do download interrompido, que
REM  por causa disso nunca chegavam a ser listados para limpeza.
if "%~2"=="0" goto ACHAR_TODOS
for /f "skip=%~2 delims=" %%A in ('dir /b /a-d /o-d %1 2^>nul') do call :ANOTAR "%%A" %3
goto :eof

:ACHAR_TODOS
for /f "delims=" %%A in ('dir /b /a-d /o-d %1 2^>nul') do call :ANOTAR "%%A" %3
goto :eof

:ANOTAR
call :PROTEGIDO "%~1"
if errorlevel 1 goto :eof
for %%F in ("%~dp0%~1") do set /a BYTES+=%%~zF
set /a TOTAL+=1
echo   %~1   -  %~2
echo %~1>> "%LISTA%"
goto :eof

REM ============================================================
REM  PROTEGIDO - lista branca. Devolve errorlevel 1 se o arquivo
REM  NAO pode ser apagado de jeito nenhum.
REM
REM  Existe porque um erro de padrao aqui apaga o agente da
REM  farmacia, e o .bat continuaria dizendo "pronto". Conferir
REM  duas vezes custa nada; restaurar custa uma visita.
REM ============================================================
:PROTEGIDO
set "N=%~nx1"
if /i "%N%"=="agente_auto.py" exit /b 1
if /i "%N%"=="mapa_xml.py" exit /b 1
if /i "%N%"=="teste_agente.py" exit /b 1
if /i "%N%"=="agente_config.json" exit /b 1
if /i "%N%"=="chave-firebase.json" exit /b 1
if /i "%N%"=="regras-firebase.json" exit /b 1
if /i "%N%"=="ultimo_publicado.json" exit /b 1
if /i "%N%"=="agente.log" exit /b 1
REM  Os ajustes_AAAA-MM-DD.json sao o registro de TODA escrita feita no
REM  Digifarma: o que era, o que virou e quem pediu. Sao a auditoria das
REM  unicas duas operacoes que este projeto grava no banco da farmacia.
REM  Nao sao log - sao a prova.
echo %N% | findstr /i /r "^ajustes_.*\.json$" >nul && exit /b 1
REM  A chave de administrador do Firebase costuma vir com o nome que o
REM  Google da: estoque-remedios-...-firebase-adminsdk-....json. Ela ignora
REM  todas as regras do banco. Some daqui e o agente para de publicar.
echo %N% | findstr /i "firebase-adminsdk serviceaccount" >nul && exit /b 1
if /i "%~x1"==".bat" exit /b 1
if /i "%~x1"==".vbs" exit /b 1
if /i "%~x1"==".ps1" exit /b 1
if /i "%~x1"==".xml" exit /b 1
if /i "%~x1"==".fdb" exit /b 1
if /i "%~x1"==".rar" exit /b 1
if /i "%~x1"==".zip" exit /b 1
exit /b 0

REM ============================================================
REM  APAGAR - so daqui sai o del, e so depois do PROTEGIDO
REM ============================================================
:APAGAR
set "ALVO=%~1"
if /i "%ALVO%"=="PASTA:__pycache__" (
  rd /s /q "%~dp0__pycache__" >nul 2>&1
  echo apagado: __pycache__\ >> "%LOG%"
  echo   apagado  __pycache__\
  goto :eof
)
call :PROTEGIDO "%ALVO%"
if errorlevel 1 (
  echo   PROTEGIDO, nao apaguei: %ALVO%
  goto :eof
)
del "%~dp0%ALVO%" >nul 2>&1
if exist "%~dp0%ALVO%" (
  echo   nao consegui apagar: %ALVO%
  echo NAO APAGADO: %ALVO% >> "%LOG%"
) else (
  echo   apagado  %ALVO%
  echo apagado: %ALVO% >> "%LOG%"
)
goto :eof

:FIM
if exist "%LISTA%" del "%LISTA%" >nul 2>&1
endlocal
