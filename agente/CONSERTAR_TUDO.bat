@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Consertar tudo - SNGPC

REM ============================================================
REM  CONSERTAR_TUDO.bat
REM
REM  Um arquivo, dois cliques, uma visita ao servidor. Foi feito
REM  para o dia em que a farmacia consegue chegar na maquina e
REM  nao sabe quando vai conseguir de novo.
REM
REM  A ORDEM IMPORTA, e ela e esta:
REM
REM    1. atualiza o agente e as regras (o resto depende disso)
REM    2. deixa a ESCRITA no Digifarma LIGADA, sem prazo
REM    3. abre o Digifarma
REM    4. abre o Anvisa.exe - PARA AQUI esperando o login
REM    5. sincroniza, ja com o inventario novo em maos
REM    6. descobre o ponteiro e oferece acertar
REM    7. colhe o diagnostico para mandar de volta
REM    8. limpa as sobras da pasta
REM
REM  O passo 5 depois do 4 de proposito: sincronizar antes do
REM  login compara com a foto velha, e o resultado nao serve.
REM
REM  O QUE ELE NAO FAZ: trocar a chave do Firebase. Isso precisa
REM  de quem tem a conta do Google, e a farmacia disse que nao
REM  tem. O TROCAR_CHAVE_FIREBASE.bat continua na pasta para
REM  quando tiver.
REM ============================================================

cd /d "%~dp0"

set "CRU=https://raw.githubusercontent.com/jeffersontete-ui/FARMACIA/main/agente"
set "PY=python"
where python >nul 2>&1
if errorlevel 1 set "PY=py"

set "LOG=%~dp0consertar_tudo_%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%.log"
set "RESP=%~dp0RESPOSTAS_DO_SERVIDOR_%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%.txt"

REM ---------- versao deste proprio arquivo ----------
REM  Mesma trava do SERVIDOR_AGORA: rodar a versao de ontem num
REM  arquivo de emergencia manda refazer o que ja foi feito. A
REM  troca mora dentro de um bloco porque o cmd le .bat linha a
REM  linha guardando a posicao - sem o bloco ele continuaria do
REM  mesmo byte no arquivo novo, no meio de outro comando.
if defined CT_JA_ATUALIZOU goto VERSAO_OK
set "CTNOVO=%TEMP%\consertar_tudo_%RANDOM%.bat"
curl -fsL -o "%CTNOVO%" "%CRU%/CONSERTAR_TUDO.bat" >nul 2>&1
if errorlevel 1 goto VERSAO_OK
if not exist "%CTNOVO%" goto VERSAO_OK
findstr /b /i /c:"@echo off" "%CTNOVO%" >nul 2>&1
if errorlevel 1 goto VERSAO_LIMPA
fc /b "%~f0" "%CTNOVO%" >nul 2>&1
if not errorlevel 1 goto VERSAO_LIMPA
echo.
echo   Saiu versao nova deste arquivo. Trocando e recomecando...
set "CT_JA_ATUALIZOU=1"
if exist "%CTNOVO%" (
  copy /y "%CTNOVO%" "%~f0" >nul
  del "%CTNOVO%" >nul 2>&1
  start "" /d "%~dp0" "%~f0" %*
  exit
)
:VERSAO_LIMPA
del "%CTNOVO%" >nul 2>&1
:VERSAO_OK

echo.
echo  ============================================================
echo   CONSERTAR TUDO - uma visita, tudo de uma vez
echo  ============================================================
echo   Tudo tambem vai para:
echo   %LOG%
echo  ============================================================
echo.
echo ==== %DATE% %TIME% ==== > "%LOG%"

REM ---------- 0. ajudantes ----------
echo  [0/8] Baixando os arquivos de apoio...
call :BAIXAR ATUALIZAR_AGENTE.bat
call :BAIXAR TROCAR_CHAVE_FIREBASE.bat
call :BAIXAR DIAGNOSTICO_ANVISA.bat
call :BAIXAR LIMPAR.bat
call :BAIXAR instalar_chromedriver.ps1
echo.

REM ---------- 1. agente e regras ----------
echo  [1/8] Atualizando o agente e as regras do Firebase...
if exist "%~dp0ATUALIZAR_AGENTE.bat" (
  call "%~dp0ATUALIZAR_AGENTE.bat" /auto
) else (
  echo        nao baixei o ATUALIZAR_AGENTE.bat; tentando pelo agente.
  %PY% agente_auto.py --atualizar
  %PY% agente_auto.py --regras
)
echo.

REM ---------- 2. a porta do Digifarma, LIGADA ----------
REM  A farmacia pediu para deixar aberta, e a decisao e dela.
REM  Fica registrado o que isso custa, porque quem decide
REM  precisa saber: os dois botoes que gravam no Digifarma
REM  passam a funcionar de qualquer celular que abra o app, sem
REM  prazo para fechar sozinha. Ligada pelo app ela vence em uma
REM  hora; ligada aqui, nao vence.
echo  [2/8] Deixando a escrita no Digifarma LIGADA, sem prazo...
REM  Ligar por aqui apaga o prazo que o app tivesse deixado. Sem
REM  isso o "sem prazo" vencia junto com um prazo antigo, calado.
%PY% agente_auto.py --config permitir_ajuste_estoque=true >> "%LOG%" 2>&1
echo        ligada. O app mostra "SEM PRAZO" na aba Servidor.
echo        Para fechar de longe: app, aba Servidor, "Desligar agora".
echo.

REM ---------- 3. o Digifarma ----------
REM  O Anvisa.exe e acessorio dele e nao abre com ele fechado.
echo  [3/8] Abrindo o Digifarma...
REM  O agente abre o Digifarma primeiro e o Anvisa.exe em seguida:
REM  o segundo e acessorio do primeiro e nao abre sozinho.
%PY% agente_auto.py --anvisa
echo        pedido feito. Veja a tela.
echo.

REM ---------- 4. o login do SNGPC ----------
echo  ============================================================
echo   [4/8] O UNICO PASSO QUE SO VOCE PODE FAZER
echo  ============================================================
echo.
echo   O Anvisa.exe deve ter aberto. Ele PARA na tela de login do
echo   site do SNGPC - e desenho da ANVISA, nao defeito.
echo.
echo   FACA O LOGIN AGORA. E ele que baixa o inventario de hoje.
echo   Sem isso, a aba Saldo continua comparando com a foto velha
echo   e os numeros nao servem para conferir prateleira.
echo.
echo   Repare em UMA coisa enquanto estiver ai: os campos de
echo   e-mail e senha ja vem preenchidos? Se vierem, o programa
echo   passa a entrar sozinho e esta visita nao precisa se
echo   repetir. Se vierem vazios, preencha na configuracao do
echo   Digifarma - e o conserto definitivo.
echo.
echo   Quando o Anvisa.exe terminar de ler o inventario, volte
echo   aqui e aperte uma tecla.
echo.
pause

REM ---------- 5. sincronizar, agora que a foto e de hoje ----------
echo.
echo  [5/8] Sincronizando com o inventario novo. Demora um pouco...
%PY% agente_auto.py --auto >> "%LOG%" 2>&1
if errorlevel 1 (
  echo        a sincronizacao falhou. O motivo esta no log.
) else (
  echo        pronto.
)
echo.

REM ---------- 6. o ponteiro ----------
echo  [6/8] Descobrindo ate qual venda o SNGPC ja recebeu...
echo.
%PY% agente_auto.py --ponteiro > "%TEMP%\ponteiro.txt" 2>&1
type "%TEMP%\ponteiro.txt"
type "%TEMP%\ponteiro.txt" >> "%LOG%"
echo.
findstr /C:"ATUALIZAR_AGENTE.bat /auto" "%TEMP%\ponteiro.txt" >nul 2>&1
if errorlevel 1 goto SEM_PONTEIRO
echo  ------------------------------------------------------------
echo   Ele achou um numero. Confira acima se faz sentido, e so
echo   entao aceite: acertar o ponteiro para o numero errado faz
echo   o Digifarma PULAR movimento que nunca subiu.
echo  ------------------------------------------------------------
set "NUM="
set /p NUM=  Numero para acertar o ponteiro, ou Enter para pular: 
if not defined NUM goto SEM_PONTEIRO
%PY% agente_auto.py --config transmitido_ate_venda=!NUM! >> "%LOG%" 2>&1
echo        gravado. O agente passa a tratar como enviado tudo ate !NUM!.
:SEM_PONTEIRO
del "%TEMP%\ponteiro.txt" >nul 2>&1
echo.

REM ---------- 7. colher ----------
echo  [7/8] Colhendo o que so daqui se descobre...
echo RESPOSTAS DO SERVIDOR - %DATE% %TIME% > "%RESP%"
call :COLHER "LOGIN DO SNGPC" --login-sngpc
call :COLHER "RETORNO DA ANVISA" --retorno-anvisa
call :COLHER "O QUE FALTA TRANSMITIR" --pendentes
call :COLHER "RESUMO DAS DIVERGENCIAS" --resumo
call :COLHER "LOG DO ANVISA.EXE" --log-anvisa
echo        pronto: %RESP%
echo.

REM ---------- 8. limpar ----------
echo  [8/8] Limpando as sobras da pasta...
if exist "%~dp0LIMPAR.bat" (
  call "%~dp0LIMPAR.bat" /simular
  echo.
  echo        Acima esta o que SAIRIA. Para apagar de verdade,
  echo        rode LIMPAR.bat depois - ele pergunta antes.
) else (
  echo        nao baixei o LIMPAR.bat; pulando.
)
echo.

echo  ============================================================
echo   TERMINOU
echo  ============================================================
echo.
echo   O QUE FICOU FEITO
echo     agente e regras atualizados
echo     escrita no Digifarma LIGADA, sem prazo
echo     inventario da ANVISA baixado, se o login foi feito
echo     numeros do app recalculados com a foto de hoje
echo.
echo   O QUE CONTINUA PENDENTE
echo     A chave do Firebase NAO foi trocada - precisa de quem
echo     tem a conta do Google. Ela saiu do servidor num .rar e
echo     continua valendo ate ser apagada no console. Quando
echo     conseguir acesso: TROCAR_CHAVE_FIREBASE.bat.
echo.
echo     O provedor Anonimo do Firebase, se ainda estiver ligado,
echo     tambem so se desliga pelo console.
echo.
echo   MANDE DE VOLTA
echo     %RESP%
echo     Confira antes - ele foi montado com lista de permissao,
echo     sem senha e sem paciente.
echo.
echo   Log completo em:
echo   %LOG%
echo  ============================================================
echo.
pause
goto FIM

REM ------------------------------------------------------------
:BAIXAR
REM  -f para o curl FALHAR em erro de HTTP. Sem ele, a pagina de
REM  erro do GitHub e gravada por cima do arquivo.
curl -fsL -o "%~dp0%~1" "%CRU%/%~1" >nul 2>&1
if errorlevel 1 (
  echo        nao baixei %~1
) else (
  echo        ok %~1
)
goto :eof

REM ------------------------------------------------------------
:COLHER
REM  %1 titulo   %2 modo do agente
echo. >> "%RESP%"
echo ============================================================ >> "%RESP%"
echo  %~1 >> "%RESP%"
echo ============================================================ >> "%RESP%"
%PY% agente_auto.py %2 >> "%RESP%" 2>&1
echo        - %~1
goto :eof

:FIM
endlocal
