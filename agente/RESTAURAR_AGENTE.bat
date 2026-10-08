@echo off
chcp 1252 >nul
title RESTAURAR O AGENTE DA LIXEIRA
setlocal enabledelayedexpansion

echo ============================================================
echo  RESTAURAR O AGENTE DA LIXEIRA
echo ============================================================
echo.
echo A pasta do agente foi apagada. As copias estao na Lixeira com
echo nomes como $R868BRZ, que nao dizem nada - mas o Windows guarda
echo o caminho original num arquivo irmao, o $I.
echo.
echo Este programa le esses arquivos, mostra de onde cada pasta veio,
echo e COPIA de volta para o lugar de origem.
echo.
echo Ele COPIA, nao move: a Lixeira continua intacta. Se ja existir
echo algo no destino, ele pula e avisa, sem sobrescrever.
echo.

set "PS=%TEMP%\restaurar_agente.ps1"
if exist "%PS%" del /f /q "%PS%" >nul 2>&1

echo $ErrorActionPreference = 'SilentlyContinue'                             >> "%PS%"
echo $achou = 0                                                              >> "%PS%"
echo foreach ($lixo in Get-ChildItem -Path 'C:\$RECYCLE.BIN' -Directory -Force) { >> "%PS%"
echo   foreach ($i in Get-ChildItem -Path $lixo.FullName -Filter '$I*' -Force) { >> "%PS%"
echo     $b = [IO.File]::ReadAllBytes($i.FullName)                           >> "%PS%"
echo     if ($b.Length -lt 28) { continue }                                  >> "%PS%"
echo     $n = [BitConverter]::ToInt32($b, 24)                                >> "%PS%"
echo     if ($n -le 0 -or $n -gt 600) { continue }                           >> "%PS%"
echo     $orig = [Text.Encoding]::Unicode.GetString($b, 28, ($n - 1) * 2)    >> "%PS%"
echo     $r = Join-Path $lixo.FullName ('$R' + $i.Name.Substring(2))         >> "%PS%"
echo     if (-not (Test-Path $r)) { continue }                               >> "%PS%"
echo     $temAgente = Test-Path (Join-Path $r 'agente_auto.py')              >> "%PS%"
echo     $temSub = (Get-ChildItem -Path $r -Filter 'agente_auto.py' -Recurse -Force ^| Measure-Object).Count -gt 0 >> "%PS%"
echo     if (-not $temAgente -and -not $temSub) { continue }                 >> "%PS%"
echo     $achou++                                                            >> "%PS%"
echo     Write-Host ''                                                       >> "%PS%"
echo     Write-Host ('  origem:   ' + $orig)                                 >> "%PS%"
echo     Write-Host ('  apagada:  ' + $i.LastWriteTime)                      >> "%PS%"
echo     if (Test-Path $orig) {                                              >> "%PS%"
echo       Write-Host '  PULADO:   ja existe algo nesse lugar'               >> "%PS%"
echo       continue                                                          >> "%PS%"
echo     }                                                                   >> "%PS%"
echo     $pai = Split-Path $orig -Parent                                     >> "%PS%"
echo     if (-not (Test-Path $pai)) { New-Item -ItemType Directory -Path $pai -Force ^| Out-Null } >> "%PS%"
echo     Copy-Item -Path $r -Destination $orig -Recurse -Force               >> "%PS%"
echo     if (Test-Path $orig) { Write-Host '  RESTAURADA' } else { Write-Host '  FALHOU ao copiar' } >> "%PS%"
echo   }                                                                     >> "%PS%"
echo }                                                                       >> "%PS%"
echo Write-Host ''                                                           >> "%PS%"
echo if ($achou -eq 0) { Write-Host '  Nao achei nenhuma pasta com agente_auto.py na Lixeira.' } >> "%PS%"
echo exit $achou                                                             >> "%PS%"

echo ------------------------------------------------------------
echo  lendo a Lixeira
echo ------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS%"
set "QUANTAS=%ERRORLEVEL%"
del /f /q "%PS%" >nul 2>&1

echo ------------------------------------------------------------
if "%QUANTAS%"=="0" goto NAO_ACHOU

echo  PRONTO
echo ------------------------------------------------------------
echo.
echo Agora rode o APONTAR_SERVIDOR.bat: ele acha a pasta restaurada
echo e atualiza o agente para o repositorio novo.
goto FIM

:NAO_ACHOU
echo  NADA A RESTAURAR
echo ------------------------------------------------------------
echo.
echo Se a Lixeira foi esvaziada, o caminho passa a ser reinstalar
echo com o INSTALAR_AGENTE.bat. Me avise que eu te guio: vai ser
echo preciso a senha do Firebird e uma chave nova do Firebase.

:FIM
echo.
echo ============================================================
pause
