@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Trocar a chave do Firebase

REM ============================================================
REM  TROCAR_CHAVE_FIREBASE.bat
REM
REM  Gera uma chave nova, testa, e so entao APAGA A VELHA no
REM  Google. Apagar a velha e o que invalida uma chave vazada -
REM  gerar uma nova sozinho nao desativa nada.
REM
REM  Quem troca e a SUA conta Google, nao a chave do agente. A
REM  chave nao pode trocar a si mesma: para isso precisaria de
REM  permissao para criar e apagar chaves, e ai uma chave vazada
REM  poderia gerar novas para sempre. O gcloud autentica voce uma
REM  vez e a rotacao passa a ser um comando.
REM
REM  Se qualquer coisa falhar, a chave antiga volta e a nova e
REM  apagada do Google. O agente nunca fica sem chave boa.
REM ============================================================

cd /d "%~dp0"

REM  Chamado pelo SERVIDOR_AGORA.bat, este arquivo parava num
REM  "pressione qualquer tecla" e travava o fluxo inteiro esperando
REM  alguem que podia nem estar na frente da tela.
set "AUTO="
if /i "%~1"=="/auto" set "AUTO=1"

REM  Onde a chave esta de verdade: quem manda e o agente_config.json,
REM  nao o palpite de que ela fica ao lado deste arquivo. Na maquina da
REM  loja a pasta do agente veio do repositorio, onde a chave nunca
REM  esteve de proposito, e este .bat parou dizendo que nao achou - com
REM  a chave existindo em outro caminho, apontada pela configuracao.
set "CHAVE=%~dp0chave-firebase.json"
set "CFG=%~dp0agente_config.json"
if not exist "%CFG%" goto CAMINHO_PRONTO

set "PYCFG="
where py >nul 2>&1 && set "PYCFG=py -3"
if not defined PYCFG ( where python >nul 2>&1 && set "PYCFG=python" )
if not defined PYCFG goto CAMINHO_PRONTO

for /f "usebackq delims=" %%K in (`%PYCFG% -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8')).get('chave_firebase') or '')" "%CFG%" 2^>nul`) do set "DOCFG=%%K"
if defined DOCFG if exist "!DOCFG!" set "CHAVE=!DOCFG!"
if defined DOCFG if not exist "!DOCFG!" echo  AVISO: o agente_config.json aponta para !DOCFG!, que nao existe.

:CAMINHO_PRONTO
for %%C in ("!CHAVE!") do set "PASTACHAVE=%%~dpC"
set "CARIMBO=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%"
set "CARIMBO=%CARIMBO: =0%"
set "BACKUP=!PASTACHAVE!chave-firebase_antes_de_%CARIMBO%.json"
set "NOVA=!PASTACHAVE!chave-firebase_nova.json"

echo.
echo  ============================================================
echo   TROCAR A CHAVE DO FIREBASE
echo  ============================================================
echo.

if not exist "%CHAVE%" (
  echo  Nao achei %CHAVE%
  echo  Sem a chave atual nao da para saber qual conta trocar.
  goto FIM
)

REM ---------- 1. de quem e a chave de hoje ----------
REM  Antes eram tres "for /f" seguidos, cada um chamando o
REM  PowerShell com um pipe escapado dentro de aspas, e cada um
REM  jogando o erro no nul. Em 26/08 os tres voltaram vazios num
REM  servidor onde o arquivo estava PERFEITO - e o .bat concluiu
REM  em voz alta que o JSON nao era de conta de servico, logo
REM  depois de imprimir "type": "service_account" na tela.
REM
REM  Duas licoes viraram este bloco: uma leitura so, num arquivo,
REM  sem pipe para o cmd escapar; e o erro do PowerShell guardado
REM  em vez de descartado. Adivinhar a causa e o que nao pode.
echo  [1/6] Lendo a chave atual...
call :LERJSON "%CHAVE%"
set "IDVELHA=!IDCHAVE!"

if not "!CONTA!"=="" goto CHAVE_OK

REM  Aqui podem ser quatro coisas com o mesmo sintoma, e a resposta
REM  de cada uma e diferente. Dizer "nao parece um JSON" para todas
REM  manda procurar no lugar errado - foi o que aconteceu em 26/08.
if not exist "%CHAVE%" goto SEM_ARQUIVO

powershell -NoProfile -Command "exit 0" >nul 2>&1
if errorlevel 1 goto SEM_POWERSHELL

REM  Se o "type" saiu, o arquivo E um JSON de conta de servico e
REM  foi lido: o que falta e so o campo. Dizer que nao e um JSON
REM  seria mentir com o proprio dado na mao.
if /i "!TIPO!"=="service_account" goto FALTA_CAMPO

goto NAO_LEU

:SEM_ARQUIVO
echo  NAO ACHEI a chave em:
echo    %CHAVE%
echo.
echo  O agente procura no mesmo lugar. Se ele esta funcionando,
echo  ela existe com outro nome ou o agente_config.json aponta
echo  para outra pasta. Confira o "chave_firebase" de:
echo    %~dp0agente_config.json
goto FIM

:SEM_POWERSHELL
echo  O ARQUIVO EXISTE, mas o PowerShell nao rodou aqui - e ele
echo  que le o JSON. Sem ele nao da para trocar a chave por este
echo  atalho; a troca continua possivel pelo console do Google.
goto FIM

:FALTA_CAMPO
echo  O arquivo E uma chave de conta de servico e foi lido - o
echo  "type" saiu certo. O que nao saiu foi o client_email.
echo  Uma chave de administrador sempre tem esse campo, entao
echo  este arquivo esta incompleto ou foi cortado no meio.
echo.
echo  Nada foi trocado. Gere outra pelo console do Google.
goto MOSTRAR_ERRO

:NAO_LEU
echo  O ARQUIVO EXISTE e o PowerShell rodou, mas nao consegui
echo  ler nada de dentro dele. O que o PowerShell respondeu esta
echo  logo abaixo - e ele que diz o motivo, nao eu.
goto MOSTRAR_ERRO

:MOSTRAR_ERRO
echo.
if exist "%PSERRO%" (
  echo  ---- resposta do PowerShell ----
  type "%PSERRO%"
  echo  --------------------------------
)
echo.
echo  As primeiras linhas do arquivo, para voce reconhecer:
powershell -NoProfile -Command "Get-Content -LiteralPath '%CHAVE%' -TotalCount 3 | ForEach-Object { $_.Substring(0, [Math]::Min(70, $_.Length)) }" 2>nul
echo.
REM  Duas chaves na mesma pasta e a confusao mais provavel: o
REM  console do Google baixa com o nome comprido dele, alguem
REM  copia, e sobra uma valida e uma pela metade.
dir /b "%~dp0*firebase-adminsdk*.json" "%~dp0*serviceaccount*.json" >nul 2>&1
if not errorlevel 1 (
  echo  E ha OUTRO arquivo de chave nesta pasta:
  dir /b "%~dp0*firebase-adminsdk*.json" "%~dp0*serviceaccount*.json" 2>nul
  echo.
  echo  O agente le so o chave-firebase.json. Se o bom for o
  echo  outro, copie o outro por cima do chave-firebase.json e
  echo  rode este arquivo de novo.
)
goto FIM

:CHAVE_OK
echo        conta ..... !CONTA!
echo        projeto ... !PROJETO!
echo        chave hoje  !IDVELHA!
echo.

REM ---------- 2. tem gcloud? ----------
echo  [2/6] Procurando o gcloud...
where gcloud >nul 2>&1
if errorlevel 1 goto SEM_GCLOUD
echo        achei.
echo.

REM ---------- 3. voce esta autenticado? ----------
echo  [3/6] Conferindo o login do Google...
set "LOGADO="
for /f "delims=" %%A in ('gcloud auth list --filter=status:ACTIVE --format="value(account)" 2^>nul') do set "LOGADO=%%A"
if "!LOGADO!"=="" (
  echo        ninguem logado. Abrindo o navegador...
  gcloud auth login
  for /f "delims=" %%A in ('gcloud auth list --filter=status:ACTIVE --format="value(account)" 2^>nul') do set "LOGADO=%%A"
)
if "!LOGADO!"=="" (
  echo        nao consegui autenticar. Nada foi trocado.
  goto FIM
)
echo        logado como !LOGADO!
echo.

REM ---------- 4. gerar a nova ----------
echo  [4/6] Gerando a chave nova...
if exist "%NOVA%" del "%NOVA%" >nul 2>&1
gcloud iam service-accounts keys create "%NOVA%" --iam-account=!CONTA! --project=!PROJETO!
if errorlevel 1 goto FALHOU_CRIAR
if not exist "%NOVA%" goto FALHOU_CRIAR

set "CONTAVELHA=!CONTA!"
call :LERJSON "%NOVA%"
if "!CONTA!"=="" goto GERADA_RUIM
if /i not "!TIPO!"=="service_account" goto GERADA_RUIM
set "IDNOVA=!IDCHAVE!"
set "CONTA=!CONTAVELHA!"
echo        chave nova  !IDNOVA!
echo.

REM ---------- 5. trocar e testar ----------
echo  [5/6] Trocando e testando...
copy /Y "%CHAVE%" "%BACKUP%" >nul
move /Y "%NOVA%" "%CHAVE%" >nul

set "PY=python"
where python >nul 2>&1
if errorlevel 1 set "PY=py"

%PY% agente_auto.py --teste
if errorlevel 1 goto TESTE_FALHOU
echo        a chave nova funciona.
echo.

REM ---------- 6. apagar a velha ----------
REM  So aqui. E este passo que invalida a chave que vazou; ate
REM  ele, as duas valem.
echo  [6/6] Apagando a chave antiga no Google...
gcloud iam service-accounts keys delete !IDVELHA! --iam-account=!CONTA! --project=!PROJETO! --quiet
if errorlevel 1 (
  echo        NAO consegui apagar a antiga. A nova ja esta valendo,
  echo        mas a velha continua aceita ate ser removida a mao em:
  echo        https://console.cloud.google.com/iam-admin/serviceaccounts
  goto FIM
)
echo        apagada. A chave que vazou nao vale mais.
echo.
echo  ------------------------------------------------------------
echo   PRONTO. Backup da anterior em:
echo   %BACKUP%
echo   Guarde fora do servidor ou apague: e uma chave valida ate
echo   o momento em que foi revogada, e nao serve mais para nada.
echo  ------------------------------------------------------------
goto FIM

:GERADA_RUIM
echo        o arquivo gerado nao parece uma chave. Nada foi trocado.
if exist "%PSERRO%" type "%PSERRO%"
set "CONTA=!CONTAVELHA!"
del "%NOVA%" >nul 2>&1
goto FIM

:TESTE_FALHOU
echo.
echo        O TESTE FALHOU com a chave nova. Voltando a anterior.
move /Y "%BACKUP%" "%CHAVE%" >nul
gcloud iam service-accounts keys delete !IDNOVA! --iam-account=!CONTA! --project=!PROJETO! --quiet >nul 2>&1
echo        a chave antiga voltou e a nova foi apagada do Google.
echo        Nada mudou. Me mande o erro acima.
goto FIM

:FALHOU_CRIAR
echo        Nao consegui gerar a chave. Motivo comum: a sua conta
echo        precisa do papel "Administrador de conta de servico"
echo        no projeto. Nada foi trocado.
goto FIM

:SEM_GCLOUD
REM  Sem o gcloud a troca e no console, mas o unico passo que
REM  PRECISA de gente e o download: o Google exige que alguem
REM  autorize. O resto - achar o arquivo, conferir, trocar,
REM  testar - o .bat faz. Quem esta fazendo isto costuma estar
REM  por acesso remoto, as vezes guiando outra pessoa por
REM  telefone; cada passo manual a menos e um erro a menos.
echo        nao achei o gcloud nesta maquina.
echo.
echo        Para a troca virar um comando so na proxima vez,
echo        instale uma vez: https://cloud.google.com/sdk/docs/install
echo.
echo        Agora vamos pelo console. Abrindo a pagina...
start "" "https://console.firebase.google.com/project/%PROJETO%/settings/serviceaccounts/adminsdk"
echo.
echo  ------------------------------------------------------------
echo   NA PAGINA QUE ABRIU:
echo     clique em "Gerar nova chave privada" e confirme.
echo     Deixe o arquivo baixar onde o navegador quiser - nao
echo     precisa mover nem renomear nada.
echo  ------------------------------------------------------------
echo.
if not defined AUTO pause

echo  Procurando a chave baixada...
call :ACHAR_BAIXADA

if "!BAIXADA!"=="" (
  echo        nao achei nenhum .json BAIXADO AGORA em Downloads, na
  echo        Area de Trabalho nem nesta pasta.
  echo.
  echo        So conta arquivo dos ultimos 15 minutos, de proposito:
  echo        chave antiga parada nesta pasta passaria por nova, e o
  echo        .bat instalaria a que vazou. Se o download demorou,
  echo        gere de novo no console e rode isto em seguida.
  goto FIM
)
echo        achei: !BAIXADA!

REM  Conferir ANTES de encostar na chave que esta funcionando. Um
REM  .json qualquer da pasta de downloads nao pode virar a
REM  credencial do agente por engano.
set "ESPERADA=!CONTA!"
call :LERJSON "!BAIXADA!"
if /i not "!CONTA!"=="!ESPERADA!" goto BAIXADA_ERRADA
set "IDNOVA=!IDCHAVE!"
set "CONTA=!ESPERADA!"
echo        chave nova  !IDNOVA!

if "!IDNOVA!"=="!IDVELHA!" (
  echo        essa e a MESMA chave que ja esta em uso. Gere uma nova
  echo        na pagina antes de continuar. Nada foi trocado.
  goto FIM
)

echo.
echo  Trocando e testando...
copy /Y "%CHAVE%" "%BACKUP%" >nul
copy /Y "!BAIXADA!" "%CHAVE%" >nul

set "PY=python"
where python >nul 2>&1
if errorlevel 1 set "PY=py"

%PY% agente_auto.py --teste
if errorlevel 1 goto MANUAL_FALHOU

del "!BAIXADA!" >nul 2>&1
echo        a chave nova funciona, e o arquivo baixado foi apagado.
echo.
echo  ------------------------------------------------------------
echo   FALTA O PASSO QUE MAIS IMPORTA
echo.
echo   Volte na pagina do console e APAGUE a chave antiga:
echo     !IDVELHA!
echo.
echo   Gerar a nova nao desativa nada. Enquanto a antiga nao for
echo   removida, a que vazou continua valendo.
echo  ------------------------------------------------------------
echo.
echo   Backup da anterior em:
echo   %BACKUP%
echo   Tire do servidor ou apague depois de conferir.
goto FIM

:BAIXADA_ERRADA
echo.
echo        Esse arquivo NAO e uma chave da conta !ESPERADA!.
echo        Nada foi trocado. Confira se baixou do projeto certo.
set "CONTA=!ESPERADA!"
goto FIM

:MANUAL_FALHOU
echo.
echo        O TESTE FALHOU com a chave nova. Voltando a anterior.
copy /Y "%BACKUP%" "%CHAVE%" >nul
echo        a chave antiga voltou. Nada mudou, e a baixada continua
echo        em !BAIXADA! caso queira olhar. Me mande o erro acima.
goto FIM

REM ============================================================
REM  LERJSON - le um .json de conta de servico e devolve em
REM  CONTA, IDCHAVE, PROJETO e TIPO. O erro do PowerShell fica
REM  em %PSERRO% para quem chamou mostrar.
REM
REM  Por que uma rotina so, e por que sem pipe:
REM
REM  Isto eram seis chamadas espalhadas, cada uma dentro de um
REM  for /f, cada uma escapando o pipe com acento circunflexo, e
REM  cada uma mandando o erro para nul. Em 26/08 o servidor
REM  respondeu o que faltava saber:
REM
REM     Token inesperado na expressao ou instrucao.
REM
REM  O acento nao e consumido pelo cmd quando o pipe esta DENTRO
REM  de aspas: chega literal no PowerShell e derruba a linha
REM  inteira. As seis estavam quebradas, e as seis estavam
REM  caladas - nenhuma delas jamais funcionou.
REM
REM  Agora a saida vai para um arquivo e volta por for /f lendo
REM  ARQUIVO, que nao passa pelo escape do cmd; e o
REM  ConvertFrom-Json recebe o texto entre parenteses, sem pipe
REM  nenhum para escapar. ReadAllText ainda tira o BOM, que o
REM  Get-Content -Raw do PowerShell 5.1 deixa passar.
REM ============================================================
:LERJSON
set "CONTA="
set "IDCHAVE="
set "PROJETO="
set "TIPO="
set "FICHA=%TEMP%\chave_ficha_%RANDOM%.txt"
if not defined PSERRO set "PSERRO=%TEMP%\chave_erro_%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $j = ConvertFrom-Json ([System.IO.File]::ReadAllText('%~1')); 'CONTA=' + $j.client_email; 'IDCHAVE=' + $j.private_key_id; 'PROJETO=' + $j.project_id; 'TIPO=' + $j.type" > "%FICHA%" 2> "%PSERRO%"
if exist "%FICHA%" for /f "usebackq tokens=1,* delims==" %%A in ("%FICHA%") do set "%%A=%%B"
del "%FICHA%" >nul 2>&1
goto :eof

REM ============================================================
REM  ACHAR_BAIXADA - o .json mais novo em Downloads, na Area de
REM  Trabalho ou nesta pasta, fora os chave-firebase*.
REM
REM  Tinha tres pipes escapados num for /f so. O mais novo sai
REM  de um foreach comparando LastWriteTime, que e o mesmo que o
REM  Sort-Object fazia e nao precisa de pipe.
REM ============================================================
:ACHAR_BAIXADA
set "BAIXADA="
set "FICHA=%TEMP%\chave_baixada_%RANDOM%.txt"
REM  RECENTE e a trava que faltava, e ela e a diferenca entre
REM  trocar a chave e trocar a chave PELA VELHA.
REM
REM  Esta pasta ja tem um estoque-remedios-...-firebase-adminsdk-
REM  ....json - a chave que vazou no .rar. A busca varre Downloads,
REM  Area de Trabalho e a PASTA ATUAL; se o download for cancelado,
REM  o mais novo que sobra e justamente esse arquivo velho. E ele
REM  passaria em todas as conferencias seguintes: e da mesma conta,
REM  e o private_key_id e diferente do que esta em uso. O .bat
REM  instalaria a chave vazada e mandaria apagar a boa.
REM
REM  Quem acabou de clicar em "Gerar nova chave privada" tem um
REM  arquivo de segundos atras. Quinze minutos e folga de sobra.
REM
REM  Ser .json recente nao basta para ser candidato. O passo 1 e o 3
REM  deste mesmo fluxo reescrevem o agente_config.json, que entao
REM  aparece como "achei" e so cai na conferencia seguinte - dizendo
REM  ao usuario que ele baixou do projeto errado, o que nao e
REM  verdade. Candidato agora precisa conter service_account.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$corte = (Get-Date).AddMinutes(-15); $p = @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), (Get-Location).Path); $b = $null; foreach ($f in @(Get-ChildItem -Path $p -Filter *.json -ErrorAction SilentlyContinue)) { if ($f.Name -like 'chave-firebase*') { continue }; if ($f.Name -like 'agente_config*') { continue }; if (-not (Select-String -Path $f.FullName -Pattern service_account -Quiet)) { continue }; if ($f.LastWriteTime -lt $corte) { continue }; if ($b -eq $null -or $f.LastWriteTime -gt $b.LastWriteTime) { $b = $f } }; if ($b -ne $null) { $b.FullName }" > "%FICHA%" 2>nul
if exist "%FICHA%" for /f "usebackq delims=" %%A in ("%FICHA%") do set "BAIXADA=%%A"
del "%FICHA%" >nul 2>&1
goto :eof

:FIM
if exist "%PSERRO%" del "%PSERRO%" >nul 2>&1
if exist "%FICHA%" del "%FICHA%" >nul 2>&1
echo.
if not defined AUTO pause
