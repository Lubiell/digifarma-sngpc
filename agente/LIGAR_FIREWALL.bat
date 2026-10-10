@echo off
chcp 1252 >nul
title LIGAR O FIREWALL DO WINDOWS
setlocal

REM  Liga o firewall do Windows sem quebrar o que funciona hoje na loja:
REM  antes de ligar, cria uma regra que libera TUDO que vem da rede local
REM  e outra que libera tudo que vem pela VPN, presa a placa da VPN. Fica
REM  bloqueado so o que chega de fora da rede local e da VPN.
REM
REM  Nao liga nada, e nada e alterado, se: nao for administrador, nao
REM  achar a faixa da rede local, ou houver alguem de fora da rede
REM  conectado agora numa porta desta maquina (ligar cortaria essa
REM  pessoa sem ninguem saber quem era).
REM
REM  Para voltar como estava:  netsh advfirewall set allprofiles state off

echo ============================================================
echo  LIGAR O FIREWALL DO WINDOWS
echo ============================================================
echo.
echo  Libera tudo da rede local e da VPN, e bloqueia o resto.
echo  Precisa de ADMINISTRADOR.
echo.

set "FARM_ARQ=%~f0"
set "FARM_PASTA=%~dp0"

where powershell >nul 2>&1
if errorlevel 1 goto SEM_POWERSHELL

REM  CMD de 32 bits abriria o PowerShell de 32 bits.
set "PSEXE=powershell"
if defined PROCESSOR_ARCHITEW6432 set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:FARM_ARQ); $m='#'+'== POWERSHELL =='; $i=$t.IndexOf($m); if ($i -lt 0) { exit 9 }; iex $t.Substring($i)"
if errorlevel 9 goto VEIO_QUEBRADO
goto FIM

:SEM_POWERSHELL
echo  PowerShell nao encontrado nesta maquina. Nada foi alterado.
goto FIM

:VEIO_QUEBRADO
echo  Este arquivo veio sem o bloco PowerShell do fim. Baixe de
echo  novo. Nada foi alterado.
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
$ProgressPreference = 'SilentlyContinue'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$log = New-Object System.Collections.Generic.List[string]
$reVpn = 'TAP-Windows|OpenVPN|ovpn-dco|Wintun'

function Dizer([string]$t) { Write-Host $t; $log.Add($t) }
function Secao([string]$t) { Dizer ''; Dizer ('-' * 60); Dizer (' ' + $t); Dizer ('-' * 60) }

function Gravar {
    $nome = 'firewall_' + (Get-Date -Format 'yyyyMMdd_HHmm') + '.txt'
    $arq = Join-Path $env:FARM_PASTA $nome
    try { [IO.File]::WriteAllLines($arq, $log) }
    catch { $arq = Join-Path $env:TEMP $nome; [IO.File]::WriteAllLines($arq, $log) }
    Write-Host ''
    Write-Host "  relatorio gravado em: $arq"
}

function Parar([string]$motivo) {
    Dizer ''
    Dizer "  PAREI: $motivo"
    Dizer '  O firewall NAO foi ligado e nada foi alterado.'
    Gravar
    exit 0
}

# Mesma conta do ACESSO_REMOTO.bat: 192.168.0.37 /24 -> 192.168.0.0/24.
function Rede([string]$ip, [int]$pref) {
    $o = @($ip.Split('.') | ForEach-Object { [double]$_ })
    $n = $o[0] * 16777216 + $o[1] * 65536 + $o[2] * 256 + $o[3]
    $bloco = [math]::Pow(2, 32 - $pref)
    $r = $n - ($n % $bloco)
    $a = [int]([math]::Floor($r / 16777216) % 256)
    $b = [int]([math]::Floor($r / 65536) % 256)
    $c = [int]([math]::Floor($r / 256) % 256)
    $d = [int]($r % 256)
    return "$a.$b.$c.$d/$pref"
}

function Privada([string]$faixa) {
    $p = [int]$faixa.Split('/')[1]
    if ($p -lt 16) { return $false }
    $o = @($faixa.Split('/')[0].Split('.') | ForEach-Object { [int]$_ })
    return (($o[0] -eq 10) -or ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) -or ($o[0] -eq 192 -and $o[1] -eq 168))
}

# O endereco e daqui de casa: a propria maquina, a rede local ou a VPN?
function DaCasa([string]$ip, [string[]]$faixas) {
    $ip = $ip -replace '^::ffff:', ''
    if ($ip -like '127.*' -or $ip -eq '::1' -or $ip -like 'fe80:*') { return $true }
    if ($ip -notmatch '^\d+\.\d+\.\d+\.\d+$') { return $false }
    foreach ($f in $faixas) {
        if ((Rede $ip ([int]$f.Split('/')[1])) -eq $f) { return $true }
    }
    return $false
}

function Processo([int]$id) {
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p) { return $p.ProcessName } else { return "pid $id" }
}

# ------------------------------------------------------------------
Secao '1. administrador'
if (-not $admin) {
    Dizer '  NAO: sem administrador.'
    Parar 'rode com o botao direito em "Executar como administrador".'
}
Dizer '  OK: rodando como administrador.'

# ------------------------------------------------------------------
Secao '2. como o firewall esta hoje'
$perfis = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
if (-not $perfis) { Parar 'nao consegui ler o firewall (servico do Firewall do Windows parado?).' }
foreach ($p in $perfis) { Dizer "  perfil $($p.Name): $(if ("$($p.Enabled)" -eq 'True') { 'LIGADO' } else { 'desligado' })" }
$svcFw = Get-Service MpsSvc -ErrorAction SilentlyContinue
if (-not $svcFw -or "$($svcFw.Status)" -ne 'Running') { Parar 'o servico do Firewall do Windows (MpsSvc) nao esta rodando.' }

# ------------------------------------------------------------------
Secao '3. rede local e VPN'
$lan = @()
$cfgs = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
    $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' -and $_.InterfaceDescription -notmatch $reVpn })
foreach ($c in $cfgs) {
    foreach ($a in @($c.IPv4Address)) {
        if ($a.IPAddress -like '169.254.*') { continue }
        $f = Rede $a.IPAddress ([int]$a.PrefixLength)
        if (Privada $f) { $lan += $f; Dizer "  rede local: $f (placa $($c.InterfaceAlias), IP $($a.IPAddress))" }
        else { Dizer "  faixa $f da placa $($c.InterfaceAlias) nao e privada: fica de fora" }
    }
}
$lan = @($lan | Select-Object -Unique)
if (-not $lan) { Parar 'nao achei a faixa da rede local. Sem ela, ligar o firewall poderia cortar o Digifarma nos terminais.' }

$vpns = @()
foreach ($v in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match $reVpn })) {
    foreach ($a in @(Get-NetIPAddress -InterfaceIndex $v.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' })) {
        $p = [int]$a.PrefixLength
        if ($p -gt 24) { $p = 24 }
        $f = Rede $a.IPAddress $p
        if ((Privada $f) -or $p -ge 24) {
            $vpns += [pscustomobject]@{ Faixa = $f; Alias = $v.Name }
            Dizer "  VPN: $f pela placa '$($v.Name)'"
        } else { Dizer "  VPN: faixa $f larga demais, fica de fora" }
    }
}
if (-not $vpns) { Dizer '  VPN: nenhuma placa de VPN com IP agora. Rode de novo com a VPN ligada para ela entrar.' }
$casa = @($lan) + @($vpns | ForEach-Object { $_.Faixa })

# Este PC e o servidor da VPN? Se for, a porta do OpenVPN tem de
# continuar aberta para a internet, senao a VPN cai e leva junto o
# acesso remoto. Do arquivo de configuracao so leio as linhas de modo,
# porta e protocolo: chave e certificado ficam onde estao.
$servidorVpn = @()
foreach ($d in @("$env:ProgramFiles\OpenVPN\config", "$env:ProgramFiles\OpenVPN\config-auto")) {
    foreach ($arq in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ovpn', '.conf' })) {
        $linhas = @(Get-Content -LiteralPath $arq.FullName -ErrorAction SilentlyContinue)
        if (-not ($linhas | Where-Object { $_ -match '^\s*(mode\s+server|server\s+\d|server-bridge)\b' })) { continue }
        $porta = 1194; $proto = 'UDP'
        foreach ($l in $linhas) {
            if ($l -match '^\s*(port|lport)\s+(\d+)') { $porta = [int]$matches[2] }
            if ($l -match '^\s*proto\s+(\S+)') { $proto = if ($matches[1] -match 'tcp') { 'TCP' } else { 'UDP' } }
        }
        $servidorVpn += [pscustomobject]@{ Arquivo = $arq.Name; Porta = $porta; Proto = $proto }
        Dizer "  este PC E SERVIDOR da VPN ($($arq.Name)): porta $porta $proto"
    }
}
if (-not $servidorVpn) { Dizer '  este PC nao e servidor da VPN (nenhuma configuracao de servidor do OpenVPN)' }

# ------------------------------------------------------------------
Secao '4. o que esta escutando nesta maquina'
$escutaTcp = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -notlike '127.*' -and $_.LocalAddress -ne '::1' })
foreach ($g in @($escutaTcp | Group-Object LocalPort | Sort-Object { [int]$_.Name })) {
    Dizer "  TCP $($g.Name): $(@($g.Group | ForEach-Object { Processo $_.OwningProcess }) | Select-Object -Unique)"
}
$portas = @($escutaTcp | ForEach-Object { [int]$_.LocalPort } | Select-Object -Unique)

# ------------------------------------------------------------------
Secao '5. alguem de fora conectado agora?'
$deFora = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object {
    $portas -contains [int]$_.LocalPort -and -not (DaCasa $_.RemoteAddress $casa) })
if ($deFora) {
    foreach ($c in $deFora) { Dizer "  porta $($c.LocalPort) ($(Processo $c.OwningProcess)) <- $($c.RemoteAddress)" }
    Parar 'tem conexao chegando de fora da rede local e da VPN. Ligar o firewall cortaria isso. Descubra o que e antes.'
}
Dizer '  ninguem de fora da rede local e da VPN conectado. Pode ligar.'

# ------------------------------------------------------------------
Secao '6. regras e firewall'
Get-NetFirewallRule -Name 'FARMACIA-REDE-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
try {
    New-NetFirewallRule -Name 'FARMACIA-REDE-LOCAL' -DisplayName 'FARMACIA - rede local liberada' -Direction Inbound -Action Allow `
        -Protocol Any -RemoteAddress $lan -Profile Any -ErrorAction Stop | Out-Null
    Dizer "  regra criada: tudo que vem de $($lan -join ', ') entra"
    $k = 0
    foreach ($v in $vpns) {
        $k++
        New-NetFirewallRule -Name "FARMACIA-REDE-VPN$k" -DisplayName "FARMACIA - VPN $k liberada" -Direction Inbound -Action Allow `
            -Protocol Any -RemoteAddress $v.Faixa -InterfaceAlias $v.Alias -Profile Any -ErrorAction Stop | Out-Null
        Dizer "  regra criada: tudo que vem de $($v.Faixa) pela placa '$($v.Alias)' entra"
    }
    $k = 0
    foreach ($s in $servidorVpn) {
        $k++
        New-NetFirewallRule -Name "FARMACIA-REDE-OPENVPN$k" -DisplayName "FARMACIA - servidor OpenVPN $k" -Direction Inbound -Action Allow `
            -Protocol $s.Proto -LocalPort $s.Porta -Program "$env:ProgramFiles\OpenVPN\bin\openvpn.exe" -Profile Any -ErrorAction Stop | Out-Null
        Dizer "  regra criada: porta $($s.Porta) $($s.Proto) do OpenVPN aberta para a internet, so para o openvpn.exe (e o servidor da VPN)"
    }
} catch {
    Get-NetFirewallRule -Name 'FARMACIA-REDE-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Parar "nao consegui criar as regras: $($_.Exception.Message)"
}

$antes = @($perfis | Where-Object { "$($_.Enabled)" -ne 'True' } | ForEach-Object { $_.Name })
if ($antes) {
    try {
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -ErrorAction Stop
    } catch {
        Parar "nao consegui ligar o firewall: $($_.Exception.Message)"
    }
}
$depois = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
foreach ($p in $depois) { Dizer "  perfil $($p.Name): $(if ("$($p.Enabled)" -eq 'True') { 'LIGADO' } else { 'desligado' })" }
$faltou = @($depois | Where-Object { "$($_.Enabled)" -ne 'True' })

# ------------------------------------------------------------------
Secao 'resultado'
if ($faltou) {
    Dizer "  ATENCAO: perfis ainda desligados: $(@($faltou | ForEach-Object { $_.Name }) -join ', ')."
} elseif ($antes) {
    Dizer "  FIREWALL LIGADO (antes desligado em: $($antes -join ', '))."
} else {
    Dizer '  o firewall ja estava ligado; so as regras da rede local e da VPN foram atualizadas.'
}
Dizer ''
Dizer '  Confira agora: abra o Digifarma num terminal da loja e veja se'
Dizer '  entra normal. Se algo parou, volte como estava com:'
Dizer '    netsh advfirewall set allprofiles state off'
Dizer ''
Dizer '  Proximo passo: rodar de novo o ACESSO_REMOTO.bat como administrador,'
Dizer '  que agora consegue ligar o SSH e o RDP presos a rede local e a VPN.'
Gravar
exit 0
