@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Agente SNGPC - atualizacao

REM ============================================================
REM  ATUALIZAR_AGENTE.bat
REM  Baixa a versao mais nova do agente, guarda a atual em backup,
REM  CONFERE se o arquivo baixado esta inteiro antes de trocar, e
REM  roda uma sincronizacao.
REM
REM  Dois cliques ............ pergunta a configuracao e espera
REM  ATUALIZAR_AGENTE.bat /auto ............... nao pergunta nada
REM  ATUALIZAR_AGENTE.bat /auto 46108 S ....... ja configura tudo
REM      2o parametro: numero da ultima venda transmitida
REM      3o parametro: S libera o app a escrever no Digifarma
REM  Parametro que nao vier NAO e alterado - de proposito: nada
REM  de mudar configuracao em silencio por causa de um default.
REM
REM  No modo /auto nao ha janela esperando: tudo vai para o
REM  atualizacao_AAAA-MM-DD.log, nesta mesma pasta.
REM
REM  Se o arquivo baixado tiver qualquer problema, nada e trocado.
REM  Agente quebrado num servidor onde ninguem esta e pior que
REM  agente desatualizado.
REM
REM  Nao precisa de administrador: nao mexe em tarefa nem em
REM  instalacao, so no agente_auto.py.
REM ============================================================

cd /d "%~dp0"

set "AUTO="
if /i "%~1"=="/auto" set "AUTO=1"
set "PONTEIRO=%~2"
set "AJUSTE=%~3"

if defined AUTO (
  set "LOG=%~dp0atualizacao_%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%.log"
  echo. >> "!LOG!"
  echo ==== %DATE% %TIME% ==================================== >> "!LOG!"
  call :principal >> "!LOG!" 2>&1
  exit /b %errorlevel%
)

call :principal
echo.
pause
exit /b %errorlevel%


REM ============================================================
:principal
REM ============================================================
echo ============================================================
echo  AGENTE SNGPC - atualizacao
echo ============================================================
echo.

REM ---------- 1. Python ----------
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY (
  echo  Python nao encontrado nesta maquina.
  echo  Rode o INSTALAR_AGENTE.bat como administrador primeiro.
  exit /b 1
)

REM ---------- 2. Backup ----------
echo [1/6] Guardando a versao atual...
set "CARIMBO=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%"
set "CARIMBO=%CARIMBO: =0%"
if exist agente_auto.py (
  copy /y agente_auto.py "agente_auto_antes_de_%CARIMBO%.py" >nul
  echo       backup: agente_auto_antes_de_%CARIMBO%.py
) else (
  echo       nao havia agente_auto.py nesta pasta ^(primeira instalacao^)
)

REM ---------- 3. Baixar ----------
echo [2/6] Baixando a versao mais nova do GitHub...
set "CRU=https://raw.githubusercontent.com/jeffersontete-ui/FARMACIA/main/agente"
set "URL=%CRU%/agente_auto.py"
curl -fsSL -o agente_auto_novo.py "%URL%"
if errorlevel 1 (
  echo       curl falhou, tentando pelo PowerShell...
  powershell -NoProfile -Command "try{Invoke-WebRequest -Uri '%URL%' -OutFile 'agente_auto_novo.py'}catch{exit 1}"
)
if not exist agente_auto_novo.py (
  echo.
  echo  Nao consegui baixar. Verifique a internet e tente de novo.
  echo  Nada foi alterado.
  exit /b 1
)

REM ---------- 4. Conferir antes de trocar ----------
echo [3/6] Conferindo o arquivo baixado...
%PY% -c "import sys;t=open('agente_auto_novo.py',encoding='utf-8').read();sys.exit(0 if len(t)>20000 and 'def principal(' in t and 'CONSULTAS' in t and compile(t,'a','exec') is not None else 1)"
if errorlevel 1 (
  echo.
  echo  O arquivo baixado esta incompleto ou com erro. NADA foi trocado:
  echo  o agente que estava rodando continua no lugar.
  del agente_auto_novo.py >nul 2>&1
  exit /b 1
)
move /y agente_auto_novo.py agente_auto.py >nul
echo       arquivo conferido e instalado

REM ---------- 4b. Os dois que acompanham o agente ----------
call :COMPANHEIRO mapa_xml.py "def comparar("
call :COMPANHEIRO teste_agente.py "def principal("

REM ---------- 5. Configuracao ----------
echo.
echo [4/6] Configuracao

if defined AUTO goto :configurar

echo.
echo  O envio ao SNGPC foi feito por outro computador? Entao o ponteiro
echo  daqui ficou para tras e o agente conta as mesmas vendas duas vezes.
echo  Informe o numero da ULTIMA VENDA que foi transmitida.
echo  Enter pula esta configuracao e deixa como esta.
echo.
set /p "PONTEIRO=  Transmitido ate a venda numero: "
echo.
echo  Liberar o app a ZERAR LOTE NEGATIVO e GRAVAR CONTAGEM no Digifarma?
echo  Sao as unicas operacoes que escrevem no Digifarma, e cada uma fica
echo  registrada com o antes, o depois e quem pediu.
echo  Enter pula e deixa como esta.
echo.
set /p "AJUSTE=  Liberar? (S/N): "

:configurar
if not "!PONTEIRO!"=="" (
  %PY% agente_auto.py --config transmitido_ate_venda=!PONTEIRO!
) else (
  echo       ponteiro: nao mexi, ficou como estava
)
if /i "!AJUSTE!"=="S" (
  %PY% agente_auto.py --config permitir_ajuste_estoque=true
) else if /i "!AJUSTE!"=="N" (
  %PY% agente_auto.py --config permitir_ajuste_estoque=false
) else (
  echo       escrita no Digifarma: nao mexi, ficou como estava
)

REM ---------- 5b. Regras do Firebase ----------
REM  O agente sabe publicar as regras sozinho desde que a farmacia
REM  perdeu o acesso ao servidor. Este arquivo continuava mandando
REM  fazer no console, no texto do fim - trabalho manual que ja era
REM  automatico, e que por isso ninguem fazia.
echo.
echo [5/6] Publicando as regras do Firebase...
%PY% agente_auto.py --regras
if errorlevel 1 (
  echo       nao consegui publicar as regras; o resto seguiu.
  echo       De para publicar a mao no console, com o conteudo de
  echo       regras-firebase.json.
)

REM ---------- 6. Rodar ----------
echo.
echo [6/6] Sincronizando...
echo.
%PY% agente_auto.py --auto
if errorlevel 1 (
  echo.
  echo  A sincronizacao falhou. O arquivo NOVO ja esta instalado; para
  echo  voltar ao anterior, renomeie o backup desta pasta para
  echo  agente_auto.py.
  exit /b 1
)

echo.
echo ============================================================
echo  PRONTO.
echo.
echo  Se apareceu o aviso de "lote(s) ja batem com a ANVISA", o
echo  ponteiro daqui esta atras do que o site ja recebeu. NAO
echo  transmita antes de acertar: seriam as mesmas vendas duas
echo  vezes. Para descobrir o numero sem perguntar a ninguem:
echo.
echo       %PY% agente_auto.py --ponteiro
echo.
echo  Ele cruza os lotes que ja batem com a ANVISA e as vendas da
echo  fila. Dando corte limpo, devolve o numero pronto.
echo.
echo  O resto do trabalho e pelo celular, na aba Servidor.
echo ============================================================
exit /b 0

REM ---------- subrotina ----------
REM  %1 nome do arquivo, %2 trecho que precisa existir dentro dele.
REM  Baixa, confere e so entao troca. Falha aqui nao derruba o update:
REM  o agente_auto.py ja esta instalado e o arquivo antigo continua
REM  servindo, com aviso na tela.
:COMPANHEIRO
curl -fsSL -o "%~1.novo" "%CRU%/%~1"
if errorlevel 1 (
  echo       AVISO: nao baixei %~1, mantido o que ja estava
  if exist "%~1.novo" del "%~1.novo" >nul 2>&1
  goto :eof
)
%PY% -c "import sys;t=open(sys.argv[1],encoding='utf-8').read();sys.exit(0 if sys.argv[2] in t and compile(t,'a','exec') is not None else 1)" "%~1.novo" %2
if errorlevel 1 (
  echo       AVISO: %~1 baixado veio quebrado, mantido o que ja estava
  del "%~1.novo" >nul 2>&1
  goto :eof
)
move /y "%~1.novo" "%~1" >nul
echo       %~1 conferido e instalado
goto :eof
