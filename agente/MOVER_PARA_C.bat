@echo off
chcp 1252 >nul
title MOVER O AGENTE PARA C:\FARMACIA-SNGPC
setlocal

REM  Leva a pasta do agente para C:\FARMACIA-SNGPC. Na Area de Trabalho
REM  ela ja sumiu duas vezes.
REM
REM  Ordem: para as tarefas, copia, confere a copia, acerta o caminho da
REM  chave no agente_config.json, recria as tarefas apontando para a pasta
REM  nova, roda a fila uma vez para provar, e so entao renomeia a pasta
REM  antiga para BACKUP_FARMACIA_<data>. Nada e apagado, a nao ser a copia
REM  da chave dentro do backup. Se algo falhar antes das tarefas novas, a
REM  pasta antiga continua valendo e as tarefas antigas voltam a rodar.
REM
REM  Este arquivo mora dentro da pasta que vai ser renomeada; por isso ele
REM  se copia para o TEMP e continua de la.

if /i "%~1"=="--temp" goto NO_TEMP
copy /y "%~f0" "%TEMP%\MOVER_PARA_C.bat" >nul
if errorlevel 1 goto SEM_TEMP
"%TEMP%\MOVER_PARA_C.bat" --temp "%~dp0"

:SEM_TEMP
echo  Nao consegui copiar este arquivo para o TEMP. Nada foi alterado.
pause
goto :eof

:NO_TEMP
set "VELHA=%~2"
if "%VELHA:~-1%"=="\" set "VELHA=%VELHA:~0,-1%"
set "NOVA=C:\FARMACIA-SNGPC"
cd /d "%TEMP%"

echo ============================================================
echo  MOVER O AGENTE PARA C:\FARMACIA-SNGPC
echo ============================================================
echo.
echo  de:   %VELHA%
echo  para: %NOVA%
echo.

net session >nul 2>&1
if errorlevel 1 goto SEM_ADMIN
if not exist "%VELHA%\agente_auto.py" goto SEM_AGENTE
if /i "%VELHA%"=="%NOVA%" goto JA_ESTA
if exist "%NOVA%\agente_auto.py" goto JA_EXISTE
dir /b /a "%NOVA%" 2>nul | findstr "^" >nul
if not errorlevel 1 goto JA_EXISTE

set "PYEXE="
for /f "delims=" %%p in ('py -3 -c "import sys;print(sys.executable)" 2^>nul') do set "PYEXE=%%p"
if not defined PYEXE goto SEM_PYTHON

echo ------------------------------------------------------------
echo  1. parando as tarefas do agente durante a copia
echo ------------------------------------------------------------
schtasks /Change /TN "AgenteSNGPC" /DISABLE >nul 2>&1
schtasks /Change /TN "AgenteSNGPC_Fila" /DISABLE >nul 2>&1
schtasks /End /TN "AgenteSNGPC" >nul 2>&1
schtasks /End /TN "AgenteSNGPC_Fila" >nul 2>&1
timeout /t 3 /nobreak >nul
echo   ok
echo.

echo ------------------------------------------------------------
echo  2. copiando
echo ------------------------------------------------------------
robocopy "%VELHA%" "%NOVA%" /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NP
if errorlevel 8 goto FALHOU_COPIA
if not exist "%NOVA%\agente_auto.py" goto FALHOU_COPIA
if exist "%VELHA%\agente_config.json" if not exist "%NOVA%\agente_config.json" goto FALHOU_COPIA
if exist "%VELHA%\chave-firebase.json" if not exist "%NOVA%\chave-firebase.json" goto FALHOU_COPIA
del "%NOVA%\MOVER_PARA_C.bat" >nul 2>&1
echo   copia conferida.
echo.

echo ------------------------------------------------------------
echo  3. so o Sistema, os Administradores e esta conta leem a pasta
echo ------------------------------------------------------------
REM  Na Area de Trabalho a pasta ja era fechada no perfil do usuario. Em
REM  C:\ ela herdaria leitura para todo usuario do Windows - e ela guarda
REM  a chave do Firebase e a senha do banco no agente_config.json.
icacls "%NOVA%" /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F "%USERNAME%":(OI)(CI)M /Q >nul
if errorlevel 1 goto FALHOU_ACL
echo   ok
echo.

echo ------------------------------------------------------------
echo  4. caminho da chave no agente_config.json
echo ------------------------------------------------------------
if not exist "%NOVA%\agente_config.json" goto SEM_CONFIG
"%PYEXE%" -c "import json,os;n=os.environ['NOVA'];v=os.environ['VELHA'];p=os.path.join(n,'agente_config.json');c=json.load(open(p,encoding='utf-8'));m=[k for k,x in c.items() if isinstance(x,str) and x.lower().startswith(v.lower()+chr(92))];[c.__setitem__(k,n+c[k][len(v):]) for k in m];f=open(p,'w',encoding='utf-8');json.dump(c,f,indent=2,ensure_ascii=False);f.close();print('  trocado: '+(', '.join(m) or 'nada apontava para a pasta antiga'))"
if errorlevel 1 goto FALHOU_CONFIG
:SEM_CONFIG
echo.

echo ------------------------------------------------------------
echo  5. tarefas apontando para a pasta nova
echo ------------------------------------------------------------
schtasks /Create /TN "AgenteSNGPC" /SC HOURLY /RL HIGHEST /RU SYSTEM /F /TR "\"%PYEXE%\" \"%NOVA%\agente_auto.py\" --auto" >nul
if errorlevel 1 goto FALHOU_TAREFA
schtasks /Create /TN "AgenteSNGPC_Fila" /SC MINUTE /MO 1 /RL HIGHEST /RU SYSTEM /F /TR "\"%PYEXE%\" \"%NOVA%\agente_auto.py\" --fila" >nul
if errorlevel 1 goto FALHOU_TAREFA
echo   AgenteSNGPC       de hora em hora
echo   AgenteSNGPC_Fila  de minuto em minuto
echo.

echo ------------------------------------------------------------
echo  6. rodando a fila uma vez, ja da pasta nova
echo ------------------------------------------------------------
schtasks /Run /TN "AgenteSNGPC_Fila" >nul
timeout /t 40 /nobreak >nul
set "RES="
for /f "delims=" %%r in ('powershell -NoProfile -Command "(Get-ScheduledTaskInfo -TaskName AgenteSNGPC_Fila).LastTaskResult"') do set "RES=%%r"
if "%RES%"=="0" goto FILA_OK
if "%RES%"=="267009" goto FILA_RODANDO
echo   A fila terminou com o codigo %RES%. As tarefas ja apontam para a
echo   pasta nova; a pasta antiga NAO foi renomeada, para dar para voltar.
echo   Veja o agente.log em %NOVA%.
goto FIM

:FILA_RODANDO
echo   A fila ainda esta rodando depois de 40 segundos. Siga assim mesmo;
echo   confira o resultado no app daqui a pouco.
goto RENOMEAR

:FILA_OK
echo   ok: a fila rodou da pasta nova sem erro.

:RENOMEAR
echo.
echo ------------------------------------------------------------
echo  7. pasta antiga vira backup
echo ------------------------------------------------------------
set "CARIMBO="
for /f "delims=" %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "CARIMBO=%%d"
set "BKP=BACKUP_FARMACIA_%CARIMBO%"
for %%P in ("%VELHA%") do set "PAI=%%~dpP"
ren "%VELHA%" "%BKP%"
if errorlevel 1 goto FALHOU_REN
REM  A chave fica so onde o agente le. O backup e copia de seguranca do
REM  resto; a chave, se um dia precisar, sai da pasta nova.
del "%PAI%%BKP%\chave-firebase.json" >nul 2>&1
echo   A pasta antiga agora e:
echo     %PAI%%BKP%
echo   A copia da chave dentro dela foi apagada. O menu ignora pastas
echo   BACKUP_FARMACIA. Depois de uns dias funcionando, pode apagar.
goto PRONTO

:FALHOU_REN
echo   Nao consegui renomear a pasta antiga: alguma janela ou programa
echo   esta com ela aberta. Feche o Explorador nessa pasta e rode:
echo     ren "%VELHA%" "%BKP%"
echo   O agente ja roda da pasta nova; isso e so para nao ficar duas
echo   copias da chave e o menu nao achar duas pastas.

:PRONTO
echo.
echo ============================================================
echo  PRONTO. O agente agora mora em %NOVA%.
echo  Confira no app, aba Servidor, se a fila responde.
goto FIM

:SEM_ADMIN
echo  PARE: rode como ADMINISTRADOR - as tarefas rodam como SYSTEM.
echo  Nada foi alterado.
goto FIM

:SEM_AGENTE
echo  Este arquivo precisa estar na pasta do agente, junto do
echo  agente_auto.py. Nada foi alterado.
goto FIM

:JA_ESTA
echo  O agente ja esta em %NOVA%. Nada a fazer.
goto FIM

:JA_EXISTE
echo  %NOVA% ja existe e nao esta vazia. Para nao misturar duas
echo  instalacoes, nada foi alterado. Confira o que tem la.
goto FIM

:SEM_PYTHON
echo  Python nao encontrado. Nada foi alterado.
goto FIM

:FALHOU_COPIA
echo  A copia nao ficou completa. As tarefas antigas voltam a rodar da
echo  pasta antiga; a copia parcial em %NOVA% pode ser apagada.
goto VOLTAR

:FALHOU_ACL
echo  Nao consegui fechar as permissoes da pasta nova. Para nao deixar
echo  a chave legivel para todos, sigo com a pasta antiga.
goto VOLTAR

:FALHOU_CONFIG
echo  Nao consegui acertar o agente_config.json da pasta nova. Sigo com
echo  a pasta antiga.
goto VOLTAR

:FALHOU_TAREFA
echo  Nao consegui recriar as tarefas. Rode o INSTALAR_AGENTE.bat como
echo  administrador dentro de %NOVA%.
goto FIM

:VOLTAR
schtasks /Change /TN "AgenteSNGPC" /ENABLE >nul 2>&1
schtasks /Change /TN "AgenteSNGPC_Fila" /ENABLE >nul 2>&1
echo  Tarefas antigas religadas.

:FIM
echo.
echo ============================================================
pause
endlocal
goto :eof
