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
REM  instalacao, so nos arquivos do agente.
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
set "CRU=https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/agente"

REM  Quais arquivos formam o agente quem diz e o arquivos.json do
REM  repositorio, o mesmo que o botao "Atualizar o agente" le. Sem ele
REM  o agente nao pode ser dividido em modulos: este caminho manual
REM  instalaria o principal novo sem o modulo que ele importa.
REM  Lido ANTES de trocar qualquer coisa: lista estranha para tudo.
REM  Sem conseguir baixar a lista, vale a fixa de sempre. A marca de
REM  cada arquivo aqui so pode ter caracteres que o CMD nao interpreta
REM  (sem " %% ! ^ & | < > \ nem acento) - mais estrito que o agente.
if exist arquivos_lista.txt del arquivos_lista.txt >nul 2>&1
curl -fsSL -o arquivos.json.novo "%CRU%/arquivos.json"
if errorlevel 1 goto :LISTA_FIXA
%PY% -c "import sys,json,re;d=json.load(open(sys.argv[1],encoding='utf-8')).get('arquivos');ok=isinstance(d,dict) and 'agente_auto.py' in d and len(d)<=30 and all(re.match(r'[a-z][a-z0-9_]*[.]py$',n) and isinstance(m,str) and m.strip() and all(31<ord(c)<127 and c not in chr(34)+chr(37)+chr(33)+chr(94)+chr(38)+chr(124)+chr(60)+chr(62)+chr(92) for c in m) for n,m in d.items());ok or sys.exit(1);open(sys.argv[2],'w',encoding='utf-8').write(''.join(n+'|'+m+chr(10) for n,m in d.items() if n not in ('agente_auto.py',)))" arquivos.json.novo arquivos_lista.txt
if errorlevel 1 (
  echo.
  echo  O arquivos.json do repositorio veio estranho. NADA foi trocado:
  echo  o agente que estava rodando continua no lugar.
  del arquivos.json.novo >nul 2>&1
  if exist arquivos_lista.txt del arquivos_lista.txt >nul 2>&1
  exit /b 1
)
del arquivos.json.novo >nul 2>&1
echo       lista de arquivos: arquivos.json do repositorio
goto :BAIXAR_PRINCIPAL

:LISTA_FIXA
if exist arquivos.json.novo del arquivos.json.novo >nul 2>&1
echo       AVISO: nao baixei o arquivos.json; vale a lista fixa
> arquivos_lista.txt echo mapa_xml.py^|def comparar^(
>> arquivos_lista.txt echo teste_agente.py^|def principal^(

:BAIXAR_PRINCIPAL
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
  del arquivos_lista.txt >nul 2>&1
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
  del arquivos_lista.txt >nul 2>&1
  exit /b 1
)
echo       agente_auto.py conferido

REM ---------- 4b. Os que acompanham o agente (lista do passo 3) ----------
REM  Todos baixados e conferidos ANTES de trocar qualquer um: principal
REM  novo sem o modulo que ele importa e agente parado no servidor.
set "FALHOU="
for /f "usebackq tokens=1,* delims=|" %%a in ("arquivos_lista.txt") do call :COMPANHEIRO %%a "%%b"
if defined FALHOU (
  echo.
  echo  Faltou arquivo do agente. NADA foi trocado: o agente que estava
  echo  rodando continua no lugar. Tente de novo mais tarde.
  del agente_auto_novo.py >nul 2>&1
  for /f "usebackq tokens=1 delims=|" %%a in ("arquivos_lista.txt") do del "%%a.novo" >nul 2>&1
  del arquivos_lista.txt >nul 2>&1
  exit /b 1
)
move /y agente_auto_novo.py agente_auto.py >nul
echo       agente_auto.py instalado
for /f "usebackq tokens=1 delims=|" %%a in ("arquivos_lista.txt") do (
  move /y "%%a.novo" "%%a" >nul
  echo       %%a instalado
)
del arquivos_lista.txt >nul 2>&1

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
echo  Junto com desmarcar controlado, sao as unicas escritas no Digifarma; cada uma fica
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
REM  So baixa e confere, para %1.novo; quem troca e o passo 4b, depois
REM  que TODOS passaram. Qualquer falha liga FALHOU e nada e trocado.
:COMPANHEIRO
curl -fsSL -o "%~1.novo" "%CRU%/%~1"
if errorlevel 1 (
  echo       FALHA: nao baixei %~1
  if exist "%~1.novo" del "%~1.novo" >nul 2>&1
  set "FALHOU=1"
  goto :eof
)
%PY% -c "import sys;t=open(sys.argv[1],encoding='utf-8').read();sys.exit(0 if sys.argv[2] in t and compile(t,'a','exec') is not None else 1)" "%~1.novo" %2
if errorlevel 1 (
  echo       FALHA: %~1 baixado veio quebrado
  del "%~1.novo" >nul 2>&1
  set "FALHOU=1"
  goto :eof
)
echo       %~1 conferido
goto :eof
