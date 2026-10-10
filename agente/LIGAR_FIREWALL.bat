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
    if ($jaLigado) { Dizer '  O firewall continua ligado como estava; nada foi alterado.' }
    else { Dizer '  O firewall NAO foi ligado e nada foi alterado.' }
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
foreach ($p in $perfis) {
    Dizer "  perfil $($p.Name): $(if ("$($p.Enabled)" -eq 'True') { 'LIGADO' } else { 'desligado' }), entrada sem regra: $($p.DefaultInboundAction)"
}
$svcFw = Get-Service MpsSvc -ErrorAction SilentlyContinue
if (-not $svcFw -or "$($svcFw.Status)" -ne 'Running') { Parar 'o servico do Firewall do Windows (MpsSvc) nao esta rodando.' }
$jaLigado = -not @($perfis | Where-Object { "$($_.Enabled)" -ne 'True' })

# Regra de bloqueio vence regra de liberacao. Com o firewall desligado ha
# tempo, pode ter sobrado bloqueio de quando alguem clicou "Cancelar" no
# aviso do Windows (fbserver, Digifarma): ligar cortaria os terminais.
$bloqueios = @(Get-NetFirewallRule -Direction Inbound -Action Block -Enabled True -ErrorAction SilentlyContinue)
if ($bloqueios -and -not $jaLigado) {
    foreach ($b in $bloqueios) {
        $prog = ($b | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program
        Dizer "  BLOQUEIO: '$($b.DisplayName)' perfil $($b.Profile), programa $prog"
    }
    Parar 'ha regras de BLOQUEIO de entrada ligadas. Elas venceriam a liberacao da rede local e poderiam cortar os terminais. Mande esta lista para decidir o que fazer com elas.'
}
Dizer "  regras de bloqueio de entrada ligadas: $($bloqueios.Count)"

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

# Uma regra por placa de VPN, ligada ou nao: presa a placa, ela so vale
# para o que chega pelo tunel. Placa desconectada agora tambem ganha a
# sua, para a VPN nao ser cortada quando voltar.
$vpns = @()
foreach ($v in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match $reVpn })) {
    $faixa = $null
    foreach ($a in @(Get-NetIPAddress -InterfaceIndex $v.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' })) {
        $p = [int]$a.PrefixLength
        if ($p -gt 24) { $p = 24 }
        $f = Rede $a.IPAddress $p
        if ((Privada $f) -or $p -ge 24) { $faixa = $f }
    }
    $vpns += [pscustomobject]@{ Alias = $v.Name; Faixa = $faixa }
    if ($faixa) { Dizer "  VPN: placa '$($v.Name)', faixa $faixa" }
    else { Dizer "  VPN: placa '$($v.Name)' sem faixa agora: libero tudo que chegar por ela" }
}
if (-not $vpns) { Dizer '  VPN: nenhuma placa de VPN nesta maquina' }
$casa = @($lan) + @($vpns | Where-Object { $_.Faixa } | ForEach-Object { $_.Faixa })

# Este PC e o servidor da VPN? Se for, a porta do OpenVPN tem de
# continuar aberta para a internet, senao a VPN cai e leva junto o
# acesso remoto. Dos arquivos de configuracao so leio as linhas de modo,
# porta e protocolo: chave e certificado ficam onde estao.
$servidorVpn = @(); $clienteVpn = 0
$pastasVpn = @("$env:ProgramFiles\OpenVPN", "${env:ProgramFiles(x86)}\OpenVPN") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
foreach ($raiz in $pastasVpn) {
    foreach ($d in @("$raiz\config", "$raiz\config-auto")) {
        foreach ($arq in @(Get-ChildItem -LiteralPath $d -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ovpn', '.conf' })) {
            $linhas = @(Get-Content -LiteralPath $arq.FullName -ErrorAction SilentlyContinue)
            if (-not ($linhas | Where-Object { $_ -match '^\s*(mode\s+server|server\s+\d|server-bridge)\b' })) {
                if ($linhas | Where-Object { $_ -match '^\s*(client|tls-client|pull)\b' }) { $clienteVpn++ }
                continue
            }
            $porta = 1194; $proto = 'UDP'
            foreach ($l in $linhas) {
                if ($l -match '^\s*(port|lport)\s+(\d+)') { $porta = [int]$matches[2] }
                if ($l -match '^\s*proto\s+(\S+)') { $proto = if ($matches[1] -match 'tcp') { 'TCP' } else { 'UDP' } }
            }
            $servidorVpn += [pscustomobject]@{ Arquivo = $arq.Name; Porta = $porta; Proto = $proto }
            Dizer "  este PC E SERVIDOR da VPN ($($arq.Name)): porta $porta $proto"
        }
    }
}
$procVpn = @(Get-Process -Name openvpn -ErrorAction SilentlyContinue)
$portasVpn = @()
foreach ($pr in $procVpn) {
    $portasVpn += @(Get-NetUDPEndpoint -OwningProcess $pr.Id -ErrorAction SilentlyContinue | ForEach-Object { "UDP $($_.LocalPort)" })
    $portasVpn += @(Get-NetTCPConnection -State Listen -OwningProcess $pr.Id -ErrorAction SilentlyContinue | ForEach-Object { "TCP $($_.LocalPort)" })
}
$portasVpn = @($portasVpn | Select-Object -Unique)
if ($portasVpn) { Dizer "  openvpn.exe com porta aberta: $($portasVpn -join ', ')" }
if (-not $servidorVpn) {
    if ($procVpn -and -not $clienteVpn) {
        Parar 'o OpenVPN esta rodando e nao achei configuracao de servidor nem de cliente. Sem saber se este PC e o servidor da VPN, ligar o firewall poderia derrubar a VPN.'
    }
    Dizer "  este PC nao e servidor da VPN ($clienteVpn configuracao(oes) de cliente)"
}
$exeVpn = $null
if ($servidorVpn) {
    $exeVpn = @($procVpn | ForEach-Object { $_.Path } | Where-Object { $_ }) | Select-Object -First 1
    if (-not $exeVpn) { $exeVpn = @($pastasVpn | ForEach-Object { "$_\bin\openvpn.exe" } | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1 }
    if (-not $exeVpn) { Parar 'este PC e servidor da VPN e nao achei o openvpn.exe para liberar a porta dele.' }
    Dizer "  programa do servidor da VPN: $exeVpn"
}

# ------------------------------------------------------------------
Secao '4. o que esta escutando nesta maquina'
$escutaTcp = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -notlike '127.*' -and $_.LocalAddress -ne '::1' })
# Esta maquina serve o banco do Digifarma: lista vazia e erro de leitura,
# nao maquina sem porta. Seguir assim seria ligar no escuro.
if (-not $escutaTcp) { Parar 'nao consegui listar as portas abertas desta maquina.' }
foreach ($g in @($escutaTcp | Group-Object LocalPort | Sort-Object { [int]$_.Name })) {
    Dizer "  TCP $($g.Name): $(@($g.Group | ForEach-Object { Processo $_.OwningProcess }) | Select-Object -Unique)"
}
$portas = @($escutaTcp | ForEach-Object { [int]$_.LocalPort } | Select-Object -Unique)
# a porta TCP do servidor da VPN continua aberta: quem esta nela nao cai
$portasServVpn = @($servidorVpn | Where-Object { $_.Proto -eq 'TCP' } | ForEach-Object { [int]$_.Porta })

# ------------------------------------------------------------------
Secao '5. alguem de fora conectado agora?'
$conexoes = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)
$deFora = @($conexoes | Where-Object {
    $portas -contains [int]$_.LocalPort -and $portasServVpn -notcontains [int]$_.LocalPort -and -not (DaCasa $_.RemoteAddress $casa) })
if ($deFora) {
    foreach ($c in $deFora) { Dizer "  porta $($c.LocalPort) ($(Processo $c.OwningProcess)) <- $($c.RemoteAddress)" }
    Parar 'tem conexao chegando de fora da rede local e da VPN. Ligar o firewall cortaria isso. Descubra o que e antes.'
}
Dizer "  ninguem de fora da rede local e da VPN conectado ($($conexoes.Count) conexao(oes) olhadas). Pode ligar."

# ------------------------------------------------------------------
Secao '6. regras e firewall'
# Regras novas primeiro, com nome desta rodada; as antigas so saem
# depois que todas as novas existem. Com o firewall ja ligado, apagar
# antes de criar deixaria a loja sem rede no meio, ou de vez se a
# criacao falhasse.
$ger = Get-Date -Format 'yyyyMMddHHmmss'
try {
    New-NetFirewallRule -Name "FARMACIA-REDE-LOCAL-$ger" -DisplayName 'FARMACIA - rede local liberada' -Direction Inbound -Action Allow `
        -Protocol Any -RemoteAddress (@($lan) + 'fe80::/10') -Profile Any -ErrorAction Stop | Out-Null
    Dizer "  regra criada: tudo que vem de $($lan -join ', ') (e IPv6 local) entra"
    $k = 0
    foreach ($v in $vpns) {
        $k++
        $remoto = if ($v.Faixa) { $v.Faixa } else { 'Any' }
        New-NetFirewallRule -Name "FARMACIA-REDE-VPN$k-$ger" -DisplayName "FARMACIA - VPN $k liberada" -Direction Inbound -Action Allow `
            -Protocol Any -RemoteAddress $remoto -InterfaceAlias $v.Alias -Profile Any -ErrorAction Stop | Out-Null
        Dizer "  regra criada: tudo que chega pela placa '$($v.Alias)' de $remoto entra"
    }
    $k = 0
    foreach ($s in $servidorVpn) {
        $k++
        New-NetFirewallRule -Name "FARMACIA-REDE-OPENVPN$k-$ger" -DisplayName "FARMACIA - servidor OpenVPN $k" -Direction Inbound -Action Allow `
            -Protocol $s.Proto -LocalPort $s.Porta -Program $exeVpn -Profile Any -ErrorAction Stop | Out-Null
        Dizer "  regra criada: porta $($s.Porta) $($s.Proto) aberta para a internet so para o openvpn.exe (servidor da VPN)"
    }
} catch {
    $erro = $_.Exception.Message
    Get-NetFirewallRule -Name "FARMACIA-REDE-*-$ger" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    if ($jaLigado) { Parar "nao consegui criar as regras novas: $erro. As regras anteriores ficaram como estavam." }
    Parar "nao consegui criar as regras: $erro"
}
Get-NetFirewallRule -Name 'FARMACIA-REDE-*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*-$ger" } |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
$nossas = @(Get-NetFirewallRule -Name "FARMACIA-REDE-*-$ger" -ErrorAction SilentlyContinue | Where-Object { "$($_.Enabled)" -eq 'True' })
Dizer "  regras da farmacia ligadas: $($nossas.Count)"

$antes = @($perfis | Where-Object { "$($_.Enabled)" -ne 'True' } | ForEach-Object { $_.Name })
if ($antes) {
    try {
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -ErrorAction Stop
    } catch {
        $erro = $_.Exception.Message
        Set-NetFirewallProfile -Profile $antes -Enabled False -ErrorAction SilentlyContinue
        Dizer ''
        Dizer "  PAREI: nao consegui ligar o firewall: $erro"
        Dizer "  Voltei a desligar os perfis que estavam desligados ($($antes -join ', ')). As regras da farmacia"
        Dizer '  ficaram criadas e nao fazem nada com o firewall desligado.'
        Gravar
        exit 0
    }
}
$depois = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
foreach ($p in $depois) {
    Dizer "  perfil $($p.Name): $(if ("$($p.Enabled)" -eq 'True') { 'LIGADO' } else { 'desligado' }), entrada sem regra: $($p.DefaultInboundAction)"
}
$faltou = @($depois | Where-Object { "$($_.Enabled)" -ne 'True' })
$liberaTudo = @($depois | Where-Object { "$($_.DefaultInboundAction)" -eq 'Allow' })

# ------------------------------------------------------------------
Secao 'resultado'
if ($faltou) {
    Dizer "  ATENCAO: perfis ainda desligados: $(@($faltou | ForEach-Object { $_.Name }) -join ', ')."
} elseif ($antes) {
    Dizer "  FIREWALL LIGADO (antes desligado em: $($antes -join ', '))."
} else {
    Dizer '  o firewall ja estava ligado; so as regras da rede local e da VPN foram atualizadas.'
}
if ($liberaTudo) {
    Dizer "  ATENCAO: nos perfis $(@($liberaTudo | ForEach-Object { $_.Name }) -join ', ') a entrada sem regra e LIBERADA: o firewall ligado nao bloqueia nada ali."
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
