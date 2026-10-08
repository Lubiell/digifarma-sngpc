@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Servidor - fazer tudo

REM ============================================================
REM  SERVIDOR_AGORA.bat  -  um arquivo, dois cliques, faz tudo.
REM
REM  Baixa sozinho o que precisa, roda a lista inteira sem
REM  perguntar nada, e no fim diz o que ficou para uma pessoa
REM  fazer - com o motivo de cada um.
REM
REM  Para o proximo, so baixar este arquivo de novo: ele traz a
REM  lista do dia junto.
REM
REM     curl -fL -o SERVIDOR_AGORA.bat https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/agente/SERVIDOR_AGORA.bat
REM
REM  So para na TROCA DA CHAVE, e so quando a maquina nao tem o
REM  gcloud: ali o Google exige que uma pessoa autorize o
REM  download. Todo o resto e automatico.
REM
REM  Nao precisa de administrador.
REM ============================================================

cd /d "%~dp0"

set "CRU=https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/agente"
set "PY=python"
where python >nul 2>&1
if errorlevel 1 set "PY=py"

set "LOG=%~dp0servidor_agora_%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%.log"

REM ============================================================
REM  Este arquivo baixava os ajudantes e esquecia de si mesmo.
REM  Em 26/08 rodou uma versao de dias antes: nao baixou o
REM  LIMPAR.bat, que ja existia, e mandou de volta uma instrucao
REM  velha - pedir a tabela do retorno da ANVISA, que ja tinha
REM  sido achada. Instrucao velha num arquivo de emergencia manda
REM  refazer o que ja foi feito.
REM
REM  Trocar o proprio arquivo enquanto ele roda e o que nao pode:
REM  o cmd le .bat linha a linha, guardando a posicao, e continua
REM  da mesma posicao no arquivo novo - no meio de outro comando.
REM  Por isso a troca e o start e o exit moram DENTRO de um bloco
REM  if: o cmd le o bloco inteiro para a memoria antes de rodar a
REM  primeira linha dele, e a janela nova comeca do zero.
REM
REM  SA_JA_ATUALIZOU impede a ida e volta sem fim se o arquivo
REM  publicado for diferente por algum motivo que nao a versao.
REM ============================================================
if not defined SA_JA_ATUALIZOU goto CONFERIR_VERSAO
goto VERSAO_CONFERIDA

:CONFERIR_VERSAO
set "SANOVO=%TEMP%\servidor_agora_novo_%RANDOM%.bat"
curl -fsL -o "%SANOVO%" "%CRU%/SERVIDOR_AGORA.bat" >nul 2>&1
if errorlevel 1 goto VERSAO_CONFERIDA
if not exist "%SANOVO%" goto VERSAO_CONFERIDA

REM  O curl com -f nao grava pagina de erro, mas um arquivo
REM  truncado ainda passa. Se nao comeca como .bat, nao entra.
findstr /b /i /c:"@echo off" "%SANOVO%" >nul 2>&1
if errorlevel 1 goto DESCARTAR_VERSAO

fc /b "%~f0" "%SANOVO%" >nul 2>&1
if not errorlevel 1 goto DESCARTAR_VERSAO

echo.
echo   Saiu versao nova deste arquivo. Trocando e recomecando...
set "SA_JA_ATUALIZOU=1"
if exist "%SANOVO%" (
  copy /y "%SANOVO%" "%~f0" >nul
  del "%SANOVO%" >nul 2>&1
  REM  start com o titulo vazio e o caminho entre aspas: o
  REM  caminho desta farmacia tem espaco - "Nova pasta" - e o
  REM  cmd /c com aspas dentro de aspas erra justamente ai.
  start "" /d "%~dp0" "%~f0" %*
  exit
)

:DESCARTAR_VERSAO
del "%SANOVO%" >nul 2>&1

:VERSAO_CONFERIDA
echo.
echo  ============================================================
echo   SERVIDOR - FAZENDO TUDO
echo  ============================================================
echo   Um passo de cada vez. O que falhar nao derruba os outros.
echo   Tudo tambem vai para:
echo   %LOG%
echo  ============================================================
echo.

echo ==== %DATE% %TIME% ==== > "%LOG%"

REM ---------- 0. trazer os ajudantes ----------
REM  Baixar antes de usar: assim este arquivo sozinho basta, e
REM  quem esta no servidor nao precisa saber que existem outros.
echo  [0/6] Baixando os arquivos de apoio...
call :BAIXAR TROCAR_CHAVE_FIREBASE.bat
call :BAIXAR DIAGNOSTICO_ANVISA.bat
call :BAIXAR instalar_chromedriver.ps1
call :BAIXAR ATUALIZAR_AGENTE.bat
call :BAIXAR LIMPAR.bat
echo.

REM ---------- 1. agente + regras ----------
echo  [1/6] Atualizando o agente e as regras do Firebase...
if exist "%~dp0ATUALIZAR_AGENTE.bat" (
  call "%~dp0ATUALIZAR_AGENTE.bat" /auto
  echo        pronto.
) else (
  echo        nao consegui baixar o ATUALIZAR_AGENTE.bat; pulando.
)
echo. >> "%LOG%"
echo ---- agente atualizado ---- >> "%LOG%"
echo.

REM ---------- 2. a chave ----------
REM  A mais importante: a chave de administrador saiu do servidor
REM  dentro de um .rar. Ela ignora todas as regras do banco.
echo  [2/6] Trocando a chave do Firebase...
if exist "%~dp0TROCAR_CHAVE_FIREBASE.bat" (
  call "%~dp0TROCAR_CHAVE_FIREBASE.bat" /auto
) else (
  echo        nao consegui baixar o TROCAR_CHAVE_FIREBASE.bat; pulando.
)
echo.

REM ---------- 3. fechar a escrita ----------
echo  [3/6] Desligando a escrita no Digifarma...
%PY% agente_auto.py --config permitir_ajuste_estoque=false >> "%LOG%" 2>&1
if errorlevel 1 (
  echo        nao consegui - veja o log.
) else (
  echo        desligada.
)
echo.

REM ---------- 4. sincronizar ----------
echo  [4/6] Sincronizando tudo. Isto demora um pouco...
%PY% agente_auto.py --auto >> "%LOG%" 2>&1
if errorlevel 1 (
  echo        falhou - veja o log.
) else (
  echo        pronto.
)
echo.

REM ---------- 5. colher o que so daqui se descobre ----------
REM  Estas perguntas ficaram semanas sem resposta porque ninguem
REM  tinha acesso a maquina. Sai tudo num arquivo so, para mandar
REM  de volta - e sem credencial nem dado de paciente: o proprio
REM  agente corta isso na origem, por lista de permissao.
echo  [5/6] Colhendo o que falta descobrir...
set "RESP=%~dp0RESPOSTAS_DO_SERVIDOR_%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2%.txt"
echo ==== %DATE% %TIME% ==== > "%RESP%"

call :COLHER "ONDE FICA O RETORNO DA ANVISA" --retorno-anvisa
call :COLHER "COLUNAS DA CAB_NOTAS" --colunas CAB_NOTAS
call :COLHER "COLUNAS DA FORNECEDORES" --colunas FORNECEDORES
call :COLHER "COLUNAS DA VENDEDORES" --colunas VENDEDORES
call :COLHER "LOGIN DO SNGPC" --login-sngpc
call :COLHER "O QUE FALTA TRANSMITIR" --pendentes
call :COLHER "LOG DO ANVISA.EXE" --log-anvisa 60

echo        pronto: %RESP%
echo.

REM ---------- 5. Anvisa ----------
REM  Aberto pela tarefa, nao daqui: com /IT ela roda na sessao de
REM  quem esta na tela. Aberto por este .bat herdaria a sessao de
REM  quem clicou, o que da no mesmo - mas pela tarefa funciona
REM  tambem quando o pedido vem do celular.
echo  [6/6] Abrindo o Anvisa.exe para o login...
%PY% agente_auto.py --anvisa >> "%LOG%" 2>&1
type "%LOG%" | findstr /I "anvisa" >nul 2>&1
echo        veja a tela: se o navegador abriu, faca o login no SNGPC.
findstr /C:"nao apareceu" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo.
  echo        NAO ABRIU, e ha alguem conectado. Entao nao e falta
  echo        de sessao. Rode agora, nesta pasta:
  echo             DIAGNOSTICO_ANVISA.bat
  echo        Ele diz se a tarefa aponta para o caminho errado ou
  echo        se o programa abre e fecha na hora.
)
echo.

echo  ============================================================
echo   O QUE SO UMA PESSOA PODE FAZER
echo  ============================================================
echo.
echo   A. ABRA O DIGIFARMA PRIMEIRO, DEPOIS FACA O LOGIN NO SNGPC
echo      O Anvisa.exe NAO ABRE com o Digifarma fechado: ele e
echo      acessorio dele. Foi o que descobrimos aqui em 26/08,
echo      depois de procurar defeito em tarefa agendada, caminho
echo      e chromedriver. Abra o Digifarma e so entao peca para
echo      abrir o Anvisa.exe.
echo.
echo      O Anvisa.exe para na tela de login - e desenho da
echo      ANVISA, nao defeito do programa. Depois do login ele le
echo      o inventario sozinho, e as divergencias que sao so foto
echo      velha somem.
echo.
echo      Enquanto estiver ai, repare em UMA coisa: os campos de
echo      e-mail e senha ja vem preenchidos? A tabela SNGPC do
echo      Digifarma guarda os dois. Se vierem vazios, o conserto
echo      e preenche-los na configuracao do Digifarma, e o
echo      programa passa a entrar sozinho.
echo.
call :SOBRE_TRANSMITIR
echo.
echo   C. MANDAR DE VOLTA O ARQUIVO DE RESPOSTAS
echo      %RESP%
echo      E por ele que o app aprende o que so existe neste
echo      servidor: nome de coluna, tabela que faltava, numero
echo      da fila. Confira antes de mandar - ele foi montado
echo      com lista de permissao, sem senha e sem paciente.
echo.
echo   D. SOBROU ARQUIVO NESTA PASTA?
echo      LIMPAR.bat mostra o que sairia e pergunta antes. Ele
echo      guarda os mais recentes de cada tipo e nunca encosta
echo      no agente, nas chaves, nos XML de envio nem nos
echo      ajustes_*.json, que sao o registro das escritas.
echo.
echo  ============================================================
echo   Log completo em:
echo   %LOG%
echo  ============================================================
echo.
pause
goto :eof

REM ------------------------------------------------------------
:BAIXAR
REM  -f para o curl FALHAR em erro de HTTP. Sem ele, a pagina de
REM  erro do GitHub e gravada por cima do arquivo - ja aconteceu
REM  aqui, e o .bat virou 199 bytes de HTML.
curl -fsL -o "%~dp0%~1" "%CRU%/%~1" >nul 2>&1
if errorlevel 1 (
  echo        nao baixei %~1
) else (
  echo        ok %~1
)
goto :eof

REM ============================================================
REM  SOBRE_TRANSMITIR - le o log e decide o que mandar fazer
REM
REM  O agente avisa quando o ponteiro deste Digifarma ficou atras
REM  do que a ANVISA ja recebeu - envio feito por outra maquina.
REM  Transmitir dali escritura a mesma venda duas vezes, e desfazer
REM  isso no SNGPC e bem pior que atrasar um dia.
REM
REM  Este arquivo mandava transmitir sem olhar. Instrucao de
REM  emergencia que nao le o proprio log manda fazer estrago.
REM ============================================================
:SOBRE_TRANSMITIR
findstr /C:"escrituraria as" "%LOG%" >nul 2>&1
if errorlevel 1 goto TRANSMITIR_NORMAL

echo   B. NAO TRANSMITA AINDA - o ponteiro esta atras
echo      O agente achou lotes que JA batem com a ANVISA sem
echo      contar o que esta na fila. Ou seja: o site ja recebeu
echo      essas vendas, e o ponteiro deste Digifarma nao andou.
echo      Transmitir daqui escrituraria tudo de novo, em dobro.
echo.
echo      Antes de transmitir, descubra ate qual venda ja subiu -
echo      quem transmitiu sabe, ou o Relatorio Status de
echo      Transmissao do site mostra. Depois:
echo.
echo         ATUALIZAR_AGENTE.bat /auto NUMERO
echo.
echo      trocando NUMERO pela ultima venda ja transmitida. Os
echo      numeros voltam ao certo e a fila passa a comecar no
echo      lugar certo. O log acima diz entre quais numeros a fila
echo      esta hoje.
goto :eof

:TRANSMITIR_NORMAL
echo   B. TRANSMITIR A MOVIMENTACAO PENDENTE
echo      No Digifarma. O passo 5 acima ja listou o que falta, no
echo      arquivo de respostas. Enquanto nao sobe, as vendas ficam
echo      contadas de um lado so.
goto :eof

REM ============================================================
REM  COLHER - roda um diagnostico e guarda no arquivo de respostas
REM  Sem parenteses em texto de echo: dentro de um bloco if eles
REM  quebram o arquivo calado. Aqui nao ha bloco, mas a regra vale
REM  para o dia em que alguem envolver isto num.
REM ============================================================
:COLHER
echo. >> "%RESP%"
echo ============================================================ >> "%RESP%"
echo  %~1 >> "%RESP%"
echo ============================================================ >> "%RESP%"
%PY% agente_auto.py %2 %3 >> "%RESP%" 2>&1
echo        - %~1
goto :eof
