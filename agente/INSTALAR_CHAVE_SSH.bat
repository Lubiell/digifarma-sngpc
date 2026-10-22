@echo off
chcp 1252 >nul
title INSTALAR CHAVE SSH NO SERVIDOR
setlocal

REM  Instala uma chave publica SSH neste servidor, para entrar de longe
REM  sem digitar senha do Windows.
REM
REM  Existe porque este servidor NAO PODE ter senha: ele precisa voltar
REM  sozinho depois de queda de luz, e conta com senha trava na tela de
REM  bloqueio. So que conta sem senha o Windows recusa no SSH e no RDP.
REM  Chave resolve os dois lados: nao manda senha nenhuma e nao mexe na
REM  entrada automatica.
REM
REM  O que NUNCA faz: criar usuario, trocar senha, abrir porta, mexer em
REM  regra de firewall ou em politica do Windows. So grava a chave no
REM  arquivo certo, acerta a permissao dele e reinicia o sshd.
REM
REM  A logica fica no bloco PowerShell no fim deste arquivo. Continua
REM  sendo um .bat so: o bloco e lido deste proprio arquivo, nada e
REM  baixado.

echo ============================================================
echo  INSTALAR CHAVE SSH NO SERVIDOR
echo ============================================================
echo.
echo  Gere a chave no celular antes, no Termux:
echo    ssh-keygen -t ed25519 -C "celular"
echo    cat ~/.ssh/id_ed25519.pub
echo.
echo  Tenha a linha que o cat mostrou a mao para colar aqui.
echo  Ela comeca com ssh-ed25519 e e UMA linha so.
echo.

set "FARM_ARQ=%~f0"

where powershell >nul 2>&1
if errorlevel 1 goto SEM_POWERSHELL

REM  CMD de 32 bits abriria o PowerShell de 32 bits, e o ProgramData do
REM  ssh cairia no lugar errado.
set "PSEXE=powershell"
if defined PROCESSOR_ARCHITEW6432 set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:FARM_ARQ); $m='#'+'== POWERSHELL =='; $i=$t.IndexOf($m); if ($i -lt 0) { exit 9 }; iex $t.Substring($i)"
if errorlevel 9 goto VEIO_QUEBRADO
goto FIM

:SEM_POWERSHELL
echo  PowerShell nao encontrado nesta maquina. Nada foi alterado.
goto FIM

:VEIO_QUEBRADO
echo  Este arquivo veio sem o bloco PowerShell do fim. Baixe de novo
echo  pelo menu. Nada foi alterado.
goto FIM

:FIM
echo.
echo ============================================================
pause
endlocal
goto :eof

#== POWERSHELL ==
# Daqui para baixo o CMD nunca chega: o goto :eof acima encerra o .bat.

$ErrorActionPreference = 'Continue'

function Parar([string]$t) { Write-Host ''; Write-Host "  $t"; exit }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Parar 'SEM ADMINISTRADOR. O arquivo de chaves mora em ProgramData e so administrador grava la. Feche, abra o menu com o botao direito em "Executar como administrador" e rode de novo. Nada foi alterado.'
}

# Sem o servico instalado a chave nao serve para nada, e gravar ela
# daria a impressao falsa de que o acesso ficou pronto.
$svc = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $svc) {
    Parar 'O Servidor OpenSSH nao esta instalado nesta maquina. Rode antes o ACESSO_REMOTO.bat, que instala o servico e prende o firewall na rede local e na VPN. Nada foi alterado.'
}
Write-Host "  servico sshd: $($svc.Status), partida $($svc.StartType)"
Write-Host ''

$colado = Read-Host '  Cole a linha da chave publica e tecle Enter'

# O celular quebra a linha na tela e o WhatsApp as vezes manda espaco a
# mais: junto tudo antes de olhar o formato.
$txt = ($colado -replace '\s+', ' ').Trim()
if ($txt -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521))\s+([A-Za-z0-9+/]+={0,2})(\s+(.*))?$') {
    Parar 'Isso nao parece uma chave publica. Ela comeca com ssh-ed25519 e e uma linha so. Copie de novo do celular, com o comando: cat ~/.ssh/id_ed25519.pub. Nada foi alterado.'
}
$tipo = $matches[1]
$b64 = $matches[2]
$comentario = if ($matches[4]) { $matches[4] } else { 'celular' }

try { $blob = [Convert]::FromBase64String($b64) }
catch { Parar 'A chave veio cortada pelo caminho: o texto nao fecha. Copie a linha inteira de novo. Nada foi alterado.' }

# Mesma conta que o OpenSSH faz: sha256 do blob, em base64, sem o '='.
$sha = [Security.Cryptography.SHA256]::Create().ComputeHash($blob)
$digital = 'SHA256:' + [Convert]::ToBase64String($sha).TrimEnd('=')
$chave = "$tipo $b64 $comentario"

Write-Host ''
Write-Host "  tipo:              $tipo"
Write-Host "  impressao digital: $digital"
Write-Host ''
Write-Host '  CONFIRA no celular, com: ssh-keygen -lf ~/.ssh/id_ed25519.pub'
Write-Host '  Se as duas nao baterem, a chave chegou errada e nao vai entrar.'

# Conta no grupo de administradores nao le o authorized_keys da propria
# pasta: o sshd do Windows manda ela para o arquivo comum, e so esse
# vale. Gravar no lugar errado falha calado.
$grupo = (Get-LocalGroup -SID 'S-1-5-32-544').Name
$souAdmin = [bool](Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq "$env:COMPUTERNAME\$env:USERNAME" })
if ($souAdmin) {
    $arq = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
} else {
    $arq = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
}
New-Item -ItemType Directory -Force -Path (Split-Path $arq) -ErrorAction SilentlyContinue | Out-Null

Write-Host ''
if ((Test-Path -LiteralPath $arq) -and (Select-String -Path $arq -SimpleMatch $b64 -Quiet)) {
    Write-Host "  esta chave ja estava instalada em: $arq"
} else {
    try {
        Add-Content -Path $arq -Value $chave -Encoding ascii -ErrorAction Stop
        Write-Host "  chave gravada em: $arq"
    } catch {
        Parar "NAO consegui gravar em $arq : $($_.Exception.Message)"
    }
}

# Arquivo que qualquer um pode escrever o sshd ignora, sem dizer nada.
if ($souAdmin) {
    & icacls $arq /inheritance:r /grant '*S-1-5-18:F' /grant '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host '  permissao acertada: so SYSTEM e administradores.' }
    else { Write-Host '  ATENCAO: nao consegui acertar a permissao do arquivo; o sshd pode ignorar a chave.' }
}

$cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
if ((Test-Path -LiteralPath $cfg) -and (Select-String -Path $cfg -Pattern '^\s*PubkeyAuthentication\s+no' -Quiet)) {
    Write-Host '  ATENCAO: o sshd_config tem PubkeyAuthentication no. Enquanto estiver assim a chave nao vale.'
}

try { Restart-Service sshd -ErrorAction Stop; Write-Host '  sshd reiniciado.' }
catch { Write-Host "  NAO consegui reiniciar o sshd: $($_.Exception.Message)" }

Write-Host ''
Write-Host '  ----------------------------------------------------------'
Write-Host '  Teste agora pelo celular, no Termux:'
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
foreach ($ip in $ips) { Write-Host "    ssh $env:USERNAME@$($ip.IPAddress)" }
if (-not $ips) { Write-Host '    (nao achei IP nesta maquina)' }
Write-Host ''
Write-Host '  Ele vai pedir a passphrase DA CHAVE, nao a senha do Windows.'
Write-Host '  Se ainda pedir "password:", a chave nao foi aceita: confira a'
Write-Host '  impressao digital acima e veja o log em:'
Write-Host "    $env:ProgramData\ssh\logs\sshd.log"
Write-Host ''
Write-Host '  Para desfazer: apague a linha desta chave em'
Write-Host "    $arq"
Write-Host '  e rode Restart-Service sshd. Nada mais foi alterado.'
exit 0
