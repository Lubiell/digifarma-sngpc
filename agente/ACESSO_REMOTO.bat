@echo off
chcp 1252 >nul
title ACESSO REMOTO AO SERVIDOR
setlocal

REM  Testa todas as formas de acessar este servidor de longe e liga as
REM  que passarem, sem perguntar nada. O servidor fica ligado 24h, entao
REM  nao ha Wake-on-LAN aqui: so acesso remoto.
REM
REM  O que NUNCA faz: abrir porta para qualquer endereco (a regra de
REM  firewall fica presa a faixa da rede local e da VPN), criar usuario,
REM  trocar senha, mexer no roteador, instalar AnyDesk ou TeamViewer.
REM
REM  A logica fica no bloco PowerShell no fim deste arquivo: calcular
REM  faixa de rede e mexer em regra de firewall em CMD puro era fragil
REM  demais. Continua sendo um .bat so: o bloco e lido deste proprio
REM  arquivo, nada e baixado.

echo ============================================================
echo  ACESSO REMOTO AO SERVIDOR
echo ============================================================
echo.
echo  Testa: administrador, placa de rede, VPN OpenVPN, edicao do
echo  Windows, OpenSSH Server, portas 22 e 3389, AnyDesk/TeamViewer
echo  e as tres tarefas do agente.
echo  Configura o que passar: SSH, firewall da porta 22 so para a
echo  rede local e a VPN, PowerShell no SSH, e RDP se for Pro.
echo.

set "FARM_ARQ=%~f0"
set "FARM_PASTA=%~dp0"

where powershell >nul 2>&1
if errorlevel 1 goto SEM_POWERSHELL

REM  CMD de 32 bits abriria o PowerShell de 32 bits: o registro do SSH
REM  cairia no WOW6432Node e o Add-WindowsCapability falharia.
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
echo  novo pelo menu. Nada foi alterado.
goto FIM

:FIM
echo.
echo ============================================================
pause
endlocal
goto :eof

#== POWERSHELL ==
# Daqui para baixo o CMD nunca chega: o goto :eof acima encerra o .bat.
# Este trecho e lido e executado pelo PowerShell chamado la em cima.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$log = New-Object System.Collections.Generic.List[string]
$resumo = New-Object System.Collections.Generic.List[string]
$reVpn = 'TAP-Windows|OpenVPN|ovpn-dco|Wintun'
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Dizer([string]$t) { Write-Host $t; $log.Add($t) }
function Secao([string]$t) { Dizer ''; Dizer ('-' * 60); Dizer (' ' + $t); Dizer ('-' * 60) }
function Resumo([string]$item, [string]$estado) { $resumo.Add(('  {0,-34} {1}' -f $item, $estado)) }

# Rede de um IP: 192.168.0.37 /24 -> 192.168.0.0/24. Conta em double,
# que guarda 32 bits exatos e nao tropeca em sinal como int32.
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

# So faixa privada entra no firewall. Faixa publica ou larga demais
# seria abrir a porta para a internet, que e exatamente o que nao pode.
function Privada([string]$faixa) {
    $p = [int]$faixa.Split('/')[1]
    if ($p -lt 16) { return $false }
    $o = @($faixa.Split('/')[0].Split('.') | ForEach-Object { [int]$_ })
    return (($o[0] -eq 10) -or ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) -or ($o[0] -eq 192 -and $o[1] -eq 168))
}

function IpPrivado([string]$ip) {
    if ($ip -notmatch '^(\d+)\.(\d+)\.\d+\.\d+$') { return $false }
    $a = [int]$matches[1]; $b = [int]$matches[2]
    return (($a -eq 10) -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or ($a -eq 192 -and $b -eq 168))
}

# Aberta = algum item do RemoteAddress sai da faixa privada: Any,
# Internet, IPv6, IP publico, ou mascara que estoura o bloco privado.
# Item a item, porque '10.0.0.0/24' contem '0.0.0.0' e nao e aberta.
function Aberta([string]$remoto) {
    foreach ($x in ($remoto -split ',')) {
        $x = $x.Trim()
        if ($x -in 'LocalSubnet', 'LocalSubnet4', 'DefaultGateway', 'DHCP', 'DNS', 'WINS') { continue }
        if ($x -match '^([\d.]+)-([\d.]+)$') {
            $de = $matches[1]; $ate = $matches[2]
            if (-not (IpPrivado $de) -or -not (IpPrivado $ate) -or $de.Split('.')[0] -ne $ate.Split('.')[0]) { return $true }
            continue
        }
        $partes = $x.Split('/')
        if (-not (IpPrivado $partes[0])) { return $true }
        if ($partes.Count -gt 1) {
            if ($partes[1] -match '\.') {
                $pref = 0
                foreach ($o in $partes[1].Split('.')) { $pref += ([Convert]::ToString([int]$o, 2) -replace '0', '').Length }
            } else { $pref = [int]$partes[1] }
            $a = [int]$partes[0].Split('.')[0]
            $minimo = if ($a -eq 10) { 8 } elseif ($a -eq 172) { 12 } else { 16 }
            if ($pref -lt $minimo) { return $true }
        }
    }
    return $false
}

function Escutando([int]$porta) {
    $quem = @()
    foreach ($c in @(Get-NetTCPConnection -State Listen -LocalPort $porta -ErrorAction SilentlyContinue)) {
        $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if ($p) { $quem += $p.ProcessName } else { $quem += "pid $($c.OwningProcess)" }
    }
    return @($quem | Select-Object -Unique)
}

function RegrasDaPorta([int]$porta) {
    $out = @()
    foreach ($pf in @(Get-NetFirewallPortFilter -All -ErrorAction SilentlyContinue | Where-Object { @($_.LocalPort) -contains "$porta" })) {
        $r = $pf | Get-NetFirewallRule -ErrorAction SilentlyContinue
        if (-not $r) { continue }
        if ("$($r.Direction)" -ne 'Inbound' -or "$($r.Action)" -ne 'Allow') { continue }
        $af = $r | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
        $out += [pscustomobject]@{
            Id = $r.Name; Nome = $r.DisplayName; Protocolo = "$($pf.Protocol)"
            Ligada = ("$($r.Enabled)" -eq 'True'); Remoto = (@($af.RemoteAddress) -join ',')
        }
    }
    return $out
}

function MostrarRegras([int]$porta) {
    $rs = @(RegrasDaPorta $porta)
    if (-not $rs) {
        $obs = if ($admin) { '' } else { ' (sem administrador a lista pode vir vazia)' }
        Dizer "  firewall $porta : nenhuma regra de entrada liberando$obs"
        return
    }
    foreach ($r in $rs) {
        $estado = if ($r.Ligada) { 'ligada' } else { 'desligada' }
        $alerta = if ($r.Ligada -and (Aberta $r.Remoto)) { '  <-- ABERTA PARA QUALQUER ENDERECO' } else { '' }
        Dizer "  firewall $porta : '$($r.Nome)' $($r.Protocolo) $estado, de: $($r.Remoto)$alerta"
    }
}

# Recria a regra da farmacia com a faixa de hoje (a VPN pode ter
# entrado ou saido desde a ultima vez) e prende a faixa em toda regra de
# outros que esteja aberta, ligada ou nao: a do proprio OpenSSH e as da
# Area de Trabalho Remota ja nascem para qualquer endereco, e uma
# desligada pode ser religada por uma atualizacao.
# Devolve $true so se, no fim, nada nesta porta ficou aberto. Quem chama
# so liga o servico com $true: com firewall desligado ou regra que nao
# deu para prender, ligar o servico seria abrir para a internet.
function Liberar([string]$id, [string]$nome, [int]$porta, [string[]]$faixas) {
    $perfis = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    $desligados = @($perfis | Where-Object { "$($_.Enabled)" -ne 'True' })
    if (-not $perfis -or $desligados) {
        Dizer "  o firewall do Windows esta DESLIGADO ($(@($desligados | ForEach-Object { $_.Name }) -join ', ')). Nao ligo o firewall sozinho, para nao derrubar o Digifarma na rede."
        return $false
    }
    $criada = $false
    try {
        Remove-NetFirewallRule -Name $id -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $id -DisplayName $nome -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $porta -RemoteAddress $faixas -Profile Any -ErrorAction Stop | Out-Null
        Dizer "  regra '$nome' criada: porta $porta so para $($faixas -join ', ')"
        $criada = $true
    } catch { Dizer "  FALHOU ao criar a regra '$nome': $($_.Exception.Message)" }
    foreach ($r in @(RegrasDaPorta $porta)) {
        if ($r.Id -eq $id -or -not (Aberta $r.Remoto)) { continue }
        try {
            Set-NetFirewallRule -Name $r.Id -RemoteAddress $faixas -ErrorAction Stop
            Dizer "  regra '$($r.Nome)' restringida: era $($r.Remoto), agora $($faixas -join ', ')"
        } catch {
            Disable-NetFirewallRule -Name $r.Id -ErrorAction SilentlyContinue
            Dizer "  nao consegui restringir a regra '$($r.Nome)' ($($_.Exception.Message)); desliguei ela"
        }
    }
    $sobra = @(RegrasDaPorta $porta | Where-Object { $_.Ligada -and (Aberta $_.Remoto) })
    foreach ($r in $sobra) { Dizer "  CONTINUA ABERTA para fora da rede: '$($r.Nome)' de $($r.Remoto)" }
    return ($criada -and -not $sobra)
}

# ------------------------------------------------------------------
Secao '1. administrador'
if ($admin) {
    Dizer '  OK: rodando como administrador.'
    Resumo 'administrador' 'sim'
} else {
    Dizer '  NAO: sem administrador. Testo tudo, mas nao configuro nada.'
    Dizer '  Para configurar: abra o menu, ou este arquivo, com o botao'
    Dizer '  direito em "Executar como administrador" e rode de novo.'
    Resumo 'administrador' 'NAO - so testei, nada configurado'
}

# ------------------------------------------------------------------
Secao '2. placa de rede'
$lanFaixas = @(); $lanIps = @()
$cfgs = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
    $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' -and $_.InterfaceDescription -notmatch $reVpn })
if (-not $cfgs) { Dizer '  NENHUMA placa ligada com gateway. Sem rede local nao ha acesso remoto.' }
foreach ($c in $cfgs) {
    $ad = $c.NetAdapter
    $midia = "$($ad.PhysicalMediaType)"
    if ($midia -match '802\.11|Wireless' -or $ad.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11') { $tipo = 'WiFi' }
    elseif ($midia -match '802\.3') { $tipo = 'cabo' }
    else { $tipo = "nao identificado (midia: $midia)" }
    Dizer "  placa:   $($ad.Name) - $($ad.InterfaceDescription)"
    Dizer "  tipo:    $tipo"
    Dizer "  MAC:     $($ad.MacAddress)"
    Dizer "  gateway: $(@($c.IPv4DefaultGateway)[0].NextHop)"
    foreach ($a in @($c.IPv4Address)) {
        if ($a.IPAddress -like '169.254.*') { continue }
        $f = Rede $a.IPAddress ([int]$a.PrefixLength)
        $origem = if ("$($a.PrefixOrigin)" -eq 'Dhcp') { 'por DHCP: pode mudar; reserve este IP no roteador' } else { 'fixo' }
        Dizer "  IP:      $($a.IPAddress)/$($a.PrefixLength) - $origem"
        Dizer "  faixa:   $f"
        if (Privada $f) { $lanFaixas += $f; $lanIps += $a.IPAddress }
        else { Dizer '  ESTA FAIXA NAO ENTRA no firewall: nao e privada, ou e larga demais.' }
    }
    Dizer ''
}
$lanFaixas = @($lanFaixas | Select-Object -Unique)
if ($lanFaixas) { Resumo 'rede local' ($lanFaixas -join ', ') } else { Resumo 'rede local' 'NAO ACHEI faixa valida' }

# ------------------------------------------------------------------
Secao '3. VPN OpenVPN'
$vpnFaixas = @(); $vpnIps = @()
$pastas = @("$env:ProgramFiles\OpenVPN", "$env:ProgramFiles\OpenVPN Connect", "${env:ProgramFiles(x86)}\OpenVPN") | Where-Object { Test-Path -LiteralPath $_ }
if ($pastas) { foreach ($p in $pastas) { Dizer "  instalado em: $p" } } else { Dizer '  pasta do OpenVPN nao encontrada em Arquivos de Programas' }
foreach ($s in @(Get-Service -Name 'OpenVPN*', 'ovpn*', 'agent_ovpn*' -ErrorAction SilentlyContinue)) {
    Dizer "  servico: $($s.Name) - $($s.Status), partida $($s.StartType)"
}
$vads = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match $reVpn })
if (-not $vads) { Dizer '  nenhum adaptador OpenVPN nesta maquina' }
foreach ($v in $vads) {
    Dizer "  adaptador: $($v.Name) - $($v.InterfaceDescription) - $($v.Status)"
    $ips = @(Get-NetIPAddress -InterfaceIndex $v.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' })
    if (-not $ips) { Dizer '    sem IP: a VPN esta desligada agora. Ligue a VPN e rode de novo para a faixa dela entrar no firewall.' }
    foreach ($a in $ips) {
        $p = [int]$a.PrefixLength
        # Em topologia net30 o adaptador recebe /30 e o celular cai em
        # outro /30 do mesmo pool: /24 cobre o pool e continua privado.
        if ($p -gt 24) { $p = 24; Dizer "    o adaptador esta em /$($a.PrefixLength); uso /24 para o celular caber no mesmo pool" }
        $f = Rede $a.IPAddress $p
        Dizer "    IP: $($a.IPAddress)/$($a.PrefixLength)   faixa: $f"
        if (Privada $f) { $vpnFaixas += $f; $vpnIps += $a.IPAddress }
        else { Dizer '    ESTA FAIXA NAO ENTRA no firewall: nao e privada, ou e larga demais.' }
    }
}
$vpnFaixas = @($vpnFaixas | Select-Object -Unique)
if ($vpnFaixas) { Resumo 'VPN' ($vpnFaixas -join ', ') } else { Resumo 'VPN' 'sem faixa (desligada ou ausente)' }

# ------------------------------------------------------------------
Secao '4. edicao do Windows'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$edicao = "$($cv.EditionID)"
$build = 0; [void][int]::TryParse("$($cv.CurrentBuild)", [ref]$build)
$versao = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10 ou anterior' }
$temRdp = $edicao -match '^(Professional|Enterprise|Education|Server|IoTEnterprise)'
Dizer "  $versao, edicao $edicao, build $build"
if ($temRdp) { Dizer '  aceita Area de Trabalho Remota (RDP).'; Resumo 'edicao do Windows' "$edicao - aceita RDP" }
else { Dizer '  NAO aceita receber Area de Trabalho Remota (edicao Home). Fica o SSH.'; Resumo 'edicao do Windows' "$edicao - sem RDP" }

# ------------------------------------------------------------------
Secao '5. OpenSSH Server'
$svc = Get-Service sshd -ErrorAction SilentlyContinue
$cap = $null
if ($admin) { $cap = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'OpenSSH.Server*' } | Select-Object -First 1 }
if ($svc) { Dizer "  servico sshd: $($svc.Status), partida $($svc.StartType)" } else { Dizer '  servico sshd: nao existe' }
if ($cap) { Dizer "  recurso opcional: $($cap.Name) - $($cap.State)" }
elseif ($admin) { Dizer '  recurso opcional OpenSSH.Server nao oferecido por este Windows' }
$shell = (Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
if ($shell) { Dizer "  shell do SSH: $shell" } else { Dizer '  shell do SSH: padrao (cmd.exe)' }

# ------------------------------------------------------------------
Secao '6. portas 22 e 3389'
foreach ($porta in 22, 3389) {
    $quem = @(Escutando $porta)
    if ($quem) { Dizer "  porta $porta : escutando ($($quem -join ', '))" } else { Dizer "  porta $porta : ninguem escutando" }
    MostrarRegras $porta
}

# ------------------------------------------------------------------
Secao '7. AnyDesk e TeamViewer'
foreach ($nome in 'AnyDesk', 'TeamViewer') {
    $ss = @(Get-Service -Name "$nome*" -ErrorAction SilentlyContinue)
    $ps = @(Get-Process -Name "$nome*" -ErrorAction SilentlyContinue)
    $no = @("$env:ProgramFiles\$nome", "${env:ProgramFiles(x86)}\$nome") | Where-Object { Test-Path -LiteralPath $_ }
    if ($ss) {
        foreach ($s in $ss) { Dizer "  $nome : servico $($s.Name) - $($s.Status), partida $($s.StartType)" }
        Dizer "    instalado como servico: entra sem ninguem na frente, se o acesso autonomo tiver senha."
        Resumo $nome "instalado ($(@($ss)[0].Status))"
    } elseif ($ps -or $no) {
        Dizer "  $nome : presente sem servico; so funciona com alguem aceitando na tela"
        Resumo $nome 'sem servico (precisa de alguem na tela)'
    } else {
        Dizer "  $nome : nao instalado. Nao instalo sozinho."
        Resumo $nome 'nao instalado'
    }
}

# ------------------------------------------------------------------
Secao '8. tarefas agendadas do agente'
$codigos = @{
    '0' = 'sucesso'; '1' = 'o programa terminou com erro'
    '267009' = 'rodando agora'; '267011' = 'ainda nao rodou'
    '2147942402' = 'arquivo nao encontrado'
    '2147942405' = 'acesso negado: costuma ser a tarefa apontando para uma PASTA'
}
foreach ($nome in 'AgenteSNGPC', 'AgenteSNGPC_Fila', 'AnvisaSNGPC_Login') {
    $t = Get-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $t) {
        $obs = if ($admin) { '' } else { ' (sem administrador a tarefa do SYSTEM pode nao aparecer)' }
        Dizer "  $nome : NAO EXISTE$obs"
        Resumo "tarefa $nome" 'nao existe'
        continue
    }
    $info = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    $u = ([int64]$info.LastTaskResult) -band 4294967295
    $hex = '0x{0:X8}' -f $u
    $txt = $codigos["$u"]; if (-not $txt) { $txt = 'codigo desconhecido' }
    Dizer "  $nome : $($t.State), ultima execucao $($info.LastRunTime), resultado $u ($hex) - $txt"
    $problema = ''
    foreach ($a in @($t.Actions)) {
        $exe = [Environment]::ExpandEnvironmentVariables(("" + $a.Execute).Trim().Trim('"'))
        $args2 = "$($a.Arguments)" -replace '(?i)((chave|token|senha|key|password|secret)\S*?[=\s]+)("[^"]*"|\S+)', '$1***'
        Dizer "    executa: $exe $args2"
        if ($exe -and (Test-Path -LiteralPath $exe -PathType Container)) {
            $problema = 'aponta para uma PASTA, nao um programa'
        } elseif ($exe -and -not (Test-Path -LiteralPath $exe -PathType Leaf) -and -not (Get-Command $exe -ErrorAction SilentlyContinue)) {
            $problema = 'o programa nao existe'
        }
        foreach ($m in [regex]::Matches("$($a.Arguments)", '"([^"]+\.(?:py|exe|bat|cmd))"')) {
            if (-not (Test-Path -LiteralPath $m.Groups[1].Value)) { $problema = "nao existe $($m.Groups[1].Value)" }
        }
        if ("$exe $($a.Arguments)" -match '\\Desktop\\|\\Area de Trabalho\\') {
            Dizer '    aviso: roda de dentro da Area de Trabalho, que ja sumiu duas vezes; o lugar certo e C:\FARMACIA-SNGPC'
        }
    }
    if ($problema) {
        Dizer "    PROBLEMA: $problema. Conserto: INSTALAR_AGENTE.bat como administrador, dentro da pasta do agente."
        Resumo "tarefa $nome" "PROBLEMA - $problema"
    } elseif ($u -eq 0 -or $u -eq 267009) {
        Resumo "tarefa $nome" 'ok'
    } else {
        Resumo "tarefa $nome" "ultimo resultado $u - $txt"
    }
}
Dizer '  (so testo as tarefas; quem conserta e o INSTALAR_AGENTE.bat)'

# ------------------------------------------------------------------
$faixas = @(@($lanFaixas) + @($vpnFaixas) | Select-Object -Unique)
$sshOk = $false; $rdpOk = $false
if (-not $admin) {
    Resumo 'configuracao' 'PULADA - sem administrador'
} elseif (-not $faixas) {
    Secao 'configuracao'
    Dizer '  PULADA: nao achei faixa de rede local nem de VPN valida.'
    Dizer '  Sem faixa eu nao abro porta nenhuma: nunca libero para qualquer endereco.'
    Resumo 'configuracao' 'PULADA - sem faixa de rede'
} else {
    Secao 'configurando o OpenSSH Server'
    $outro = @(Escutando 22 | Where-Object { $_ -ne 'sshd' })
    if ($outro) {
        Dizer "  PULADO: a porta 22 ja e de outro programa ($($outro -join ', ')). Nao mexo nele."
        Resumo 'SSH' "PULADO - porta 22 ocupada por $($outro -join ', ')"
    } else {
        if (-not $svc) {
            if (-not $cap) {
                Dizer '  este Windows nao oferece o OpenSSH Server (precisa do Windows 10 1809 ou mais novo).'
            } else {
                Dizer '  instalando o recurso opcional OpenSSH Server. Vem do Windows Update e pode levar minutos...'
                try { Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null; Dizer '  instalado.' }
                catch { Dizer "  FALHOU a instalacao: $($_.Exception.Message)" }
                $svc = Get-Service sshd -ErrorAction SilentlyContinue
            }
        }
        if ($svc) {
            try {
                if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction Stop | Out-Null }
                New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $psExe -PropertyType String -Force -ErrorAction Stop | Out-Null
                Dizer "  shell do SSH: $psExe"
            } catch { Dizer "  FALHOU ao trocar o shell: $($_.Exception.Message)" }
            $seguro = $false
            try { $seguro = Liberar 'FARMACIA-SSH-22' 'FARMACIA - SSH (porta 22)' 22 $faixas }
            catch { Dizer "  FALHOU no firewall da porta 22: $($_.Exception.Message)" }
            if ($seguro) {
                try {
                    Set-Service sshd -StartupType Automatic -ErrorAction Stop
                    Start-Service sshd -ErrorAction Stop
                    Dizer '  servico sshd ligado, partida automatica.'
                } catch { Dizer "  FALHOU ao ligar o sshd: $($_.Exception.Message)" }
            } else {
                Stop-Service sshd -ErrorAction SilentlyContinue
                Set-Service sshd -StartupType Disabled -ErrorAction SilentlyContinue
                Dizer '  SSH DESLIGADO: o firewall nao ficou preso a rede local e a VPN. Veja acima.'
            }
        }
        Start-Sleep -Seconds 2
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        $sshOk = ($svc -and "$($svc.Status)" -eq 'Running' -and (@(Escutando 22) -contains 'sshd'))
        if ($sshOk) { Resumo 'SSH' 'LIGADO e escutando na 22' } else { Resumo 'SSH' 'NAO ficou de pe - veja acima' }
    }

    Secao 'configurando a Area de Trabalho Remota'
    if (-not $temRdp) {
        Dizer "  PULADO: edicao $edicao nao recebe RDP."
        Resumo 'RDP' 'PULADO - Windows Home'
    } else {
        $seguro = $false
        try { $seguro = Liberar 'FARMACIA-RDP-3389' 'FARMACIA - RDP (porta 3389)' 3389 $faixas }
        catch { Dizer "  FALHOU no firewall da porta 3389: $($_.Exception.Message)" }
        $ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        try {
            if ($seguro) {
                Set-ItemProperty "$ts\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1 -ErrorAction Stop
                Set-ItemProperty $ts -Name fDenyTSConnections -Value 0 -ErrorAction Stop
                Start-Service TermService -ErrorAction SilentlyContinue
                Dizer '  RDP ligado, com autenticacao de rede (NLA).'
            } else {
                Set-ItemProperty $ts -Name fDenyTSConnections -Value 1 -ErrorAction Stop
                Dizer '  RDP DESLIGADO: o firewall nao ficou preso a rede local e a VPN. Veja acima.'
            }
        } catch { Dizer "  FALHOU: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
        $rdpOk = [bool](@(Escutando 3389))
        if ($rdpOk) { Resumo 'RDP' 'LIGADO e escutando na 3389' } else { Resumo 'RDP' 'NAO ficou escutando - veja acima' }
    }

    Secao 'firewall depois da configuracao'
    MostrarRegras 22
    if ($temRdp) { MostrarRegras 3389 }
}

# ------------------------------------------------------------------
Secao 'como entrar pelo celular'
$usuario = $env:USERNAME
$conta = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
if ($conta) {
    if ("$($conta.PrincipalSource)" -eq 'MicrosoftAccount') { $quando = 'conta Microsoft: a senha e a da conta Microsoft' }
    elseif ($conta.PasswordLastSet) { $quando = "senha trocada pela ultima vez em $($conta.PasswordLastSet)" }
    else { $quando = 'nao achei data de senha; conta sem senha o Windows recusa no SSH e no RDP' }
    Dizer "  conta: $usuario ($($conta.PrincipalSource)), $quando"
}
if (-not $sshOk) { Dizer '  ATENCAO: o SSH nao esta de pe; os comandos abaixo so funcionam depois de rodar isto como administrador.' }
Dizer ''
Dizer '  No Termux:'
Dizer '    pkg install openssh'
foreach ($ip in $lanIps) { Dizer "    ssh $usuario@$ip        (na rede da farmacia)" }
foreach ($ip in $vpnIps) { Dizer "    ssh $usuario@$ip        (de fora, com a VPN ligada no celular)" }
if (-not $lanIps -and -not $vpnIps) { Dizer '    (sem IP valido para montar o comando)' }
Dizer '  A senha pedida e a do Windows desta conta, nao o PIN.'
Dizer '  Nao crio usuario nem troco senha.'
if ($rdpOk) {
    Dizer ''
    Dizer '  Area de Trabalho Remota: app "Windows App" da Microsoft,'
    Dizer "  adicionar PC com o IP acima e o usuario $usuario."
}

# ------------------------------------------------------------------
Secao 'resumo'
foreach ($l in $resumo) { Dizer $l }

$nomeArq = 'acesso_remoto_' + (Get-Date -Format 'yyyyMMdd_HHmm') + '.txt'
$arq = Join-Path $env:FARM_PASTA $nomeArq
try { [IO.File]::WriteAllLines($arq, $log) }
catch { $arq = Join-Path $env:TEMP $nomeArq; [IO.File]::WriteAllLines($arq, $log) }
Write-Host ''
Write-Host "  relatorio gravado em: $arq"
exit 0
