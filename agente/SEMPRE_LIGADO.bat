@echo off
chcp 1252 >nul
title SEMPRE LIGADO - ponte da cotacao e receitas
setlocal

REM  Deixa o servidor trabalhando sozinho depois de qualquer reinicio:
REM  falta de luz, Windows Update de madrugada, alguem que desligou.
REM
REM  A ponte da cotacao so roda com alguem logado no Windows. Em 06/11
REM  ela parou as 02:51 e ficou parada: o PC reiniciou de madrugada e
REM  ficou na tela de entrada, sem ninguem para entrar. Este arquivo:
REM
REM    1. tira o suspender e o hibernar
REM    2. impede o Windows Update de reiniciar com alguem logado
REM    3. faz o Windows ENTRAR SOZINHO na conta depois de reiniciar
REM    4. acha a ponte e cria um vigia que religa ela se cair
REM    5. faz o agente das receitas rodar ja no boot, e o Firebird
REM       subir sozinho
REM
REM  Rode uma vez, como ADMINISTRADOR. Pode rodar de novo: refaz igual.
REM
REM  Se ele nao achar a ponte sozinho, passe o arquivo dela:
REM     SEMPRE_LIGADO.bat "C:\caminho\da\ponte.bat"
REM
REM  Para desfazer, os comandos saem no fim da tela.

echo ============================================================
echo  SEMPRE LIGADO - ponte da cotacao e servidor das receitas
echo ============================================================
echo.
echo  Precisa de ADMINISTRADOR.
echo.

set "FARM_ARQ=%~f0"
set "FARM_PASTA=%~dp0"
set "FARM_PONTE=%~1"

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
$falta = New-Object System.Collections.Generic.List[string]
$CASA = Join-Path $env:ProgramData 'SempreLigado'
$VIGIA = 'PonteCotacao_Vigia'

function Dizer([string]$t) { Write-Host $t; $log.Add($t) }
function Secao([string]$t) { Dizer ''; Dizer ('-' * 60); Dizer (' ' + $t); Dizer ('-' * 60) }

function Gravar {
    $nome = 'sempre_ligado_' + (Get-Date -Format 'yyyyMMdd_HHmm') + '.txt'
    $arq = Join-Path $env:FARM_PASTA $nome
    try { [IO.File]::WriteAllLines($arq, $log) }
    catch { $arq = Join-Path $env:TEMP $nome; [IO.File]::WriteAllLines($arq, $log) }
    Write-Host ''
    Write-Host "  relatorio gravado em: $arq"
}

if (-not $admin) {
    Dizer '  PAREI: precisa de ADMINISTRADOR. Nada foi alterado.'
    Dizer '  Clique com o botao direito no arquivo > Executar como administrador.'
    Gravar
    exit 0
}

# A conta que esta no teclado deste PC, nao a conta do administrador
# que abriu esta janela: e nela que a ponte roda.
$usuario = (Get-CimInstance Win32_ComputerSystem).UserName
if (-not $usuario) { $usuario = "$env:USERDOMAIN\$env:USERNAME" }
$partes = $usuario.Split('\', 2)
if ($partes.Count -eq 2) { $dominio = $partes[0]; $nome = $partes[1] } else { $dominio = $env:COMPUTERNAME; $nome = $usuario }
Dizer "  conta deste PC: $dominio\$nome"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SempreLigado {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LogonUser(string u, string d, string p, int tipo, int prov, out IntPtr tok);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    // 0 = senha confere; senao, o codigo de erro do Windows
    public static int Conferir(string u, string d, string p) {
        IntPtr tok;
        if (LogonUser(u, d, p, 2, 0, out tok)) { CloseHandle(tok); return 0; }
        return Marshal.GetLastWin32Error();
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_STR { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_ATTR { public int Length; public IntPtr Root; public IntPtr Name; public uint Attr; public IntPtr Sd; public IntPtr Qos; }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr sys, ref LSA_ATTR a, uint acesso, out IntPtr h);
    [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr h, ref LSA_STR chave, ref LSA_STR dado);
    [DllImport("advapi32.dll", EntryPoint = "LsaStorePrivateData")] static extern uint LsaApagar(IntPtr h, ref LSA_STR chave, IntPtr nada);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr h);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint s);

    static LSA_STR Str(string s) {
        LSA_STR r = new LSA_STR();
        r.Buffer = Marshal.StringToHGlobalUni(s);
        r.Length = (ushort)(s.Length * 2);
        r.MaximumLength = (ushort)(s.Length * 2 + 2);
        return r;
    }

    // Guarda a senha cifrada no LSA, onde o login automatico do Windows
    // procura - o mesmo lugar que o Autologon da Sysinternals usa. No
    // registro ela ficaria em texto puro.
    public static int Guardar(string chave, string valor) {
        LSA_ATTR a = new LSA_ATTR();
        a.Length = Marshal.SizeOf(typeof(LSA_ATTR));
        IntPtr h;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref a, 0x000F0FFF, out h);
        if (st != 0) return LsaNtStatusToWinError(st);
        LSA_STR k = Str(chave);
        LSA_STR v = Str(valor);
        try { st = LsaStorePrivateData(h, ref k, ref v); }
        finally {
            Marshal.FreeHGlobal(k.Buffer);
            Marshal.FreeHGlobal(v.Buffer);
            LsaClose(h);
        }
        return LsaNtStatusToWinError(st);
    }

    // Senha guardada de uma vez anterior: o Winlogon le o LSA antes do
    // registro, e uma senha velha ali faz o login automatico falhar.
    public static int Apagar(string chave) {
        LSA_ATTR a = new LSA_ATTR();
        a.Length = Marshal.SizeOf(typeof(LSA_ATTR));
        IntPtr h;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref a, 0x000F0FFF, out h);
        if (st != 0) return LsaNtStatusToWinError(st);
        LSA_STR k = Str(chave);
        try { st = LsaApagar(h, ref k, IntPtr.Zero); }
        finally { Marshal.FreeHGlobal(k.Buffer); LsaClose(h); }
        // 2 = nao havia nada guardado: tambem serve
        int e = LsaNtStatusToWinError(st);
        return (e == 2) ? 0 : e;
    }
}
'@

# ------------------------------------------------------------------
Secao '1. Energia: nao suspender, nao hibernar'
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
# hibernar desligado leva junto a "inicializacao rapida", que faz o
# desligar virar hibernar e pular a entrada da conta
powercfg /hibernate off | Out-Null
Dizer '  ok: na tomada o PC nao suspende nem hiberna mais'
Dizer '      o monitor pode apagar: isso nao para nada'

# ------------------------------------------------------------------
Secao '2. Windows Update: nao reiniciar com a conta aberta'
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
# New-Item -Force em chave que ja existe apaga os valores dela
if (-not (Test-Path $au)) { New-Item -Path $au -Force | Out-Null }
Set-ItemProperty -Path $au -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -Type DWord
Dizer '  ok: com a conta aberta o Update espera alguem reiniciar'
Dizer '      reiniciar para terminar atualizacao passa a ser manual: uma vez por mes'
$ed = (Get-CimInstance Win32_OperatingSystem).Caption
if ($ed -match 'Home') {
    Dizer "  aviso: $ed ignora essa regra. O item 3 cobre: se reiniciar,"
    Dizer '         a conta entra sozinha e a ponte volta.'
}

# ------------------------------------------------------------------
Secao '3. Entrar sozinho no Windows depois de reiniciar'
Dizer "  A conta $nome vai entrar sozinha toda vez que o PC ligar."
Dizer '  Quem chegar no teclado do servidor encontra a conta aberta.'
Write-Host ''
$seg = Read-Host -AsSecureString "  Senha da conta $nome (so Enter se ela NAO tem senha)"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
$senha = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$erro = [SempreLigado]::Conferir($nome, $dominio, $senha)
# 1327: o Windows recusa senha em branco fora da tela de entrada, mas a
# tela de entrada aceita. Em branco e 1327 quer dizer: conta sem senha.
$semSenha = ($senha -eq '' -and ($erro -eq 0 -or $erro -eq 1327))
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($erro -ne 0 -and -not $semSenha) {
    if ($erro -eq 1326) { Dizer '  PULEI: a senha nao confere. Nada mudou na entrada da conta.' }
    else { Dizer "  PULEI: o Windows recusou conferir a senha, erro $erro. Nada mudou na entrada." }
    $falta.Add('Rodar de novo e digitar a senha certa da conta: sem isso, depois de reiniciar o PC fica parado na tela de entrada e a ponte nao volta.')
} else {
    Set-ItemProperty -Path $wl -Name 'AutoAdminLogon' -Value '1' -Type String
    Set-ItemProperty -Path $wl -Name 'DefaultUserName' -Value $nome -Type String
    Set-ItemProperty -Path $wl -Name 'DefaultDomainName' -Value $dominio -Type String
    Remove-ItemProperty -Path $wl -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
    if ($semSenha) {
        [SempreLigado]::Apagar('DefaultPassword') | Out-Null
        Set-ItemProperty -Path $wl -Name 'DefaultPassword' -Value '' -Type String
        Dizer '  ok: conta sem senha, vai entrar sozinha'
    } else {
        Remove-ItemProperty -Path $wl -Name 'DefaultPassword' -ErrorAction SilentlyContinue
        $r = [SempreLigado]::Guardar('DefaultPassword', $senha)
        if ($r -eq 0) { Dizer '  ok: senha conferida e guardada cifrada no Windows, nao no registro' }
        else {
            Set-ItemProperty -Path $wl -Name 'AutoAdminLogon' -Value '0' -Type String
            Dizer "  PULEI: nao consegui guardar a senha, erro $r. Login automatico ficou desligado."
            $falta.Add('Login automatico nao ligou: rodar de novo, ou usar o Autologon da Microsoft/Sysinternals.')
        }
    }
    # Windows 10/11 com "so Windows Hello" esconde o login automatico
    $pl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
    if (Test-Path $pl) { Set-ItemProperty -Path $pl -Name 'DevicePasswordLessBuildVersion' -Value 0 -Type DWord }
}
$senha = $null

# ------------------------------------------------------------------
Secao '4. A ponte da cotacao: achar e vigiar'
if (-not (Test-Path $CASA)) { New-Item -ItemType Directory -Path $CASA -Force | Out-Null }
$cfgArq = Join-Path $CASA 'ponte.json'
$achados = New-Object System.Collections.Generic.List[object]
$shell = New-Object -ComObject WScript.Shell

function Juntar([string]$exe, [string]$argumentos, [string]$pasta, [string]$onde) {
    if (-not $exe) { return }
    $exe = $exe.Trim().Trim('"')
    if (("$exe $argumentos") -match 'SEMPRE_LIGADO|vigia_ponte') { return }
    $cmd = '"' + $exe + '"'
    if ($argumentos) { $cmd += ' ' + $argumentos.Trim() }
    # python ponte.py: a pasta de trabalho e a do script, nao a do python
    if (-not $pasta -and $argumentos) {
        foreach ($tk in [regex]::Matches($argumentos, '"[^"]+"|\S+')) {
            $c = $tk.Value.Trim('"')
            if ($c -match '^[A-Za-z]:\\' -and (Test-Path $c -PathType Leaf)) { $pasta = Split-Path -Parent $c; break }
        }
    }
    if (-not $pasta) { $pasta = Split-Path -Parent $exe }
    if (-not $pasta -or -not (Test-Path $pasta)) { $pasta = $env:SystemRoot }
    foreach ($a in $achados) { if ($a.comando -eq $cmd) { return } }
    $achados.Add([pscustomobject]@{ onde = $onde; comando = $cmd; pasta = $pasta })
}

# a linha "C:\x\y.exe" -a -b  ->  exe e argumentos
function Partir([string]$linha) {
    $linha = $linha.Trim()
    if ($linha.StartsWith('"')) {
        $f = $linha.IndexOf('"', 1)
        if ($f -gt 0) { return @($linha.Substring(1, $f - 1), $linha.Substring($f + 1)) }
    }
    $m = [regex]::Match($linha, '^(.+?\.(exe|bat|cmd|vbs|ps1|py|pyw|js|lnk))(\s|$)(.*)$', 'IgnoreCase')
    if ($m.Success) { return @($m.Groups[1].Value, $m.Groups[4].Value) }
    $sp = $linha.IndexOf(' ')
    if ($sp -lt 0) { return @($linha, '') }
    return @($linha.Substring(0, $sp), $linha.Substring($sp + 1))
}

if ($env:FARM_PONTE) {
    if (Test-Path $env:FARM_PONTE) {
        $f = Get-Item $env:FARM_PONTE
        if ($f.Extension -eq '.lnk') {
            $l = $shell.CreateShortcut($f.FullName)
            Juntar $l.TargetPath $l.Arguments $l.WorkingDirectory 'informado na linha de comando'
        } else { Juntar $f.FullName '' $f.DirectoryName 'informado na linha de comando' }
    } else { Dizer "  aviso: nao existe o arquivo informado: $env:FARM_PONTE" }
}

if ($achados.Count -eq 0 -and (Test-Path $cfgArq)) {
    try {
        $c = Get-Content $cfgArq -Raw | ConvertFrom-Json
        $achados.Add([pscustomobject]@{ onde = 'guardado da vez anterior'; comando = $c.comando; pasta = $c.pasta })
    } catch { }
}

if ($achados.Count -eq 0) {
    # pastas Inicializar: de todos e de cada conta
    $pastas = @(Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
    foreach ($u in Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue) {
        $pastas += Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
    }
    foreach ($p in $pastas) {
        foreach ($f in Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ponte' }) {
            if ($f.Extension -eq '.lnk') {
                $l = $shell.CreateShortcut($f.FullName)
                Juntar $l.TargetPath $l.Arguments $l.WorkingDirectory ("Inicializar: " + $f.FullName)
            } else { Juntar $f.FullName '' $f.DirectoryName ("Inicializar: " + $f.FullName) }
        }
    }
    # Run do registro: da maquina e das contas carregadas
    $runs = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')
    foreach ($h in Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
        $runs += 'Registry::' + $h.Name + '\Software\Microsoft\Windows\CurrentVersion\Run'
    }
    foreach ($r in $runs) {
        $k = Get-ItemProperty -Path $r -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($v in $k.PSObject.Properties) {
            if ($v.Name -like 'PS*') { continue }
            if (("$($v.Name) $($v.Value)") -match 'ponte') {
                $x = Partir ([string]$v.Value)
                Juntar $x[0] $x[1] '' ("registro Run: " + $v.Name)
            }
        }
    }
    # tarefas agendadas
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        if ($t.TaskName -eq $VIGIA) { continue }
        foreach ($a in $t.Actions) {
            if (("$($t.TaskName) $($a.Execute) $($a.Arguments)") -match 'ponte') {
                Juntar $a.Execute $a.Arguments $a.WorkingDirectory ("tarefa agendada: " + $t.TaskName)
            }
        }
    }
    # o que esta rodando agora
    foreach ($p in Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) {
        if (-not $p.CommandLine -or $p.CommandLine -notmatch 'ponte') { continue }
        $x = Partir $p.CommandLine
        Juntar $x[0] $x[1] '' ("rodando agora, processo " + $p.ProcessId)
    }
}

# o que identifica a ponte na lista de processos: o arquivo dela, nao
# o python/node/cmd/powershell que a roda
function Marca([string]$comando) {
    $interp = '^(python|pythonw|py|pyw|node|cmd|wscript|cscript|powershell|pwsh|java|javaw)\.exe$'
    $arqs = @([regex]::Matches($comando, '"[^"]+"|\S+') | ForEach-Object { $_.Value.Trim('"') } |
        Where-Object { $_ -match '\.(py|pyw|js|mjs|cjs|bat|cmd|vbs|ps1|exe|jar)$' } |
        ForEach-Object { Split-Path -Leaf $_ })
    $m = $arqs | Where-Object { $_ -match 'ponte' } | Select-Object -First 1
    if (-not $m) { $m = $arqs | Where-Object { $_ -notmatch $interp } | Select-Object -First 1 }
    if (-not $m) { $m = $arqs | Select-Object -First 1 }
    return $m
}

$escolha = $null
$pulou = $false
$marcas = @($achados | ForEach-Object { Marca $_.comando } | Where-Object { $_ } | Sort-Object -Unique)
if ($achados.Count -eq 1) { $escolha = $achados[0] }
elseif ($achados.Count -gt 1 -and $marcas.Count -eq 1) {
    # o mesmo arquivo achado em lugares diferentes (atalho e processo
    # rodando): e uma ponte so. Fico com o comando que esta rodando agora,
    # que e o que comprovadamente funciona.
    $escolha = $achados | Where-Object { $_.onde -like 'rodando agora*' } | Select-Object -First 1
    if (-not $escolha) { $escolha = $achados[0] }
    Dizer ("  Achei a ponte em " + $achados.Count + " lugares, todos o mesmo arquivo: " + $marcas[0])
}
elseif ($achados.Count -gt 1) {
    Dizer '  Achei mais de um jeito de abrir a ponte:'
    for ($i = 0; $i -lt $achados.Count; $i++) {
        Dizer ("   " + ($i + 1) + " - " + $achados[$i].comando)
        Dizer ("       " + $achados[$i].onde)
    }
    $n = Read-Host '  Numero do certo (Enter pula)'
    if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $achados.Count) { $escolha = $achados[[int]$n - 1] }
    else { $pulou = $true }
}

if (-not $escolha -and $pulou) {
    Dizer '  Escolha pulada. O vigia NAO foi criado: rode de novo e digite o numero.'
    $falta.Add('Vigia da ponte: rodar de novo e escolher o numero da ponte na lista.')
} elseif (-not $escolha) {
    Dizer '  Nao achei a ponte neste PC. O vigia NAO foi criado.'
    Dizer '  Se ela abre sozinha quando a conta entra, o item 3 ja resolve'
    Dizer '  o reinicio. Para ela voltar tambem quando cair, rode de novo'
    Dizer '  passando o arquivo dela:'
    Dizer '     SEMPRE_LIGADO.bat "C:\caminho\da\ponte.bat"'
    $falta.Add('Vigia da ponte: rodar de novo com o caminho da ponte - nao achei sozinho.')
} else {
    $marca = Marca $escolha.comando

    if (-not $marca) {
        Dizer "  Nao entendi qual arquivo e a ponte em: $($escolha.comando)"
        Dizer '  O vigia NAO foi criado. Rode de novo passando o arquivo dela.'
        $falta.Add('Vigia da ponte: rodar de novo com o caminho da ponte.')
    } else {
        Dizer "  ponte: $($escolha.comando)"
        Dizer "         achada em: $($escolha.onde)"
        Dizer "         reconheco rodando por: $marca"
        $viva = @(Get-CimInstance Win32_Process | Where-Object {
            $_.CommandLine -and $_.CommandLine -like ('*' + $marca + '*') -and
            $_.CommandLine -notlike '*vigia_ponte*' -and $_.CommandLine -notlike '*SEMPRE_LIGADO*' })
        $seguir = $true
        if ($viva.Count -gt 0) { Dizer '  ok: a ponte esta rodando agora e eu reconheco ela' }
        else {
            Dizer "  Nao vejo nada rodando com $marca agora."
            $r = Read-Host '  A ponte esta ABERTA agora neste PC? Digite SIM se esta, Enter se nao'
            if ($r -match '^\s*sim\s*$') {
                # aberta e eu nao reconheco: o vigia abriria outra a cada 5 min
                Dizer '  PULEI o vigia: ele nao reconheceria a ponte e abriria outra.'
                Dizer '  Rode de novo passando o arquivo que fica rodando, o .exe ou .py:'
                Dizer '     SEMPRE_LIGADO.bat "C:\caminho\da\ponte.py"'
                $falta.Add('Vigia da ponte: rodar de novo com o arquivo que fica rodando - o informado so abre a ponte e sai.')
                $seguir = $false
            }
        }
    }
    if ($marca -and $seguir) {
        [pscustomobject]@{ comando = $escolha.comando; pasta = $escolha.pasta; marca = $marca } |
            ConvertTo-Json | Set-Content -Path $cfgArq -Encoding UTF8

        $ps1 = Join-Path $CASA 'vigia_ponte.ps1'
        $vbs = Join-Path $CASA 'vigia_ponte.vbs'
        @'
# Vigia da ponte da cotacao, criado pelo SEMPRE_LIGADO.bat.
# Roda de 5 em 5 minutos com a conta aberta: se a ponte nao esta na
# lista de processos, abre de novo. Nao faz mais nada.
$cfg = Get-Content (Join-Path $PSScriptRoot 'ponte.json') -Raw | ConvertFrom-Json
$viva = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and $_.CommandLine -like ('*' + $cfg.marca + '*') -and
    $_.CommandLine -notlike '*vigia_ponte*' -and $_.CommandLine -notlike '*SEMPRE_LIGADO*' }
if ($viva) { exit 0 }
$log = Join-Path $PSScriptRoot 'vigia_ponte.log'
if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Remove-Item $log -Force }
# trava: se abriu 3 vezes na ultima hora e nao ficou de pe, para de abrir
$hora = (Get-Date).AddHours(-1).ToString('yyyy-MM-dd HH:mm:ss')
if (Test-Path $log) {
    $vezes = @(Get-Content $log | Where-Object { $_ -match 'abrindo de novo' -and $_.Substring(0, 19) -gt $hora }).Count
    if ($vezes -ge 3) { exit 0 }
}
Add-Content -Path $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ponte parada: abrindo de novo')
Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c start "" ' + $cfg.comando) -WorkingDirectory $cfg.pasta -WindowStyle Hidden
'@ | Set-Content -Path $ps1 -Encoding UTF8
        # o .vbs abre o PowerShell sem piscar janela a cada 5 minutos
        ('CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $ps1 + '""", 0, False') |
            Set-Content -Path $vbs -Encoding ASCII

        $acao = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbs + '"')
        # 2 minutos depois de entrar: a ponte abre sozinha antes, se abria;
        # o vigia nao abre uma segunda
        $gat = New-ScheduledTaskTrigger -AtLogOn -User "$dominio\$nome"
        $gat.Delay = 'PT2M'
        $gat.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)).Repetition
        $quem = New-ScheduledTaskPrincipal -UserId "$dominio\$nome" -LogonType Interactive -RunLevel Limited
        $cfgT = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        try {
            Register-ScheduledTask -TaskName $VIGIA -Action $acao -Trigger $gat -Principal $quem -Settings $cfgT -Force -ErrorAction Stop | Out-Null
            Dizer "  ok: tarefa $VIGIA - ao entrar e de 5 em 5 minutos"
            Start-ScheduledTask -TaskName $VIGIA -ErrorAction SilentlyContinue
            Dizer '  vigia rodou agora: se a ponte estava parada, ja abriu de novo'
            Dizer "  registro do que o vigia fez: $CASA\vigia_ponte.log"
        } catch {
            Dizer "  FALHOU criar a tarefa do vigia: $($_.Exception.Message)"
            $falta.Add('Vigia da ponte nao foi criado: ver o erro no relatorio.')
        }
    }
}

# ------------------------------------------------------------------
Secao '5. Servidor das receitas: agente SNGPC e Firebird'
# As tarefas rodam como SYSTEM: nao dependem de ninguem entrar. Falta
# so rodar logo depois do boot, e nao desistir por bateria ou por ter
# perdido o horario com o PC desligado.
foreach ($n in @('AgenteSNGPC', 'AgenteSNGPC_Fila')) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    if (-not $t) {
        Dizer "  FALTA a tarefa ${n}: o agente nao esta instalado aqui."
        $falta.Add("Instalar o agente das receitas nesta maquina - FARMACIA.bat, opcao 9 - a tarefa $n nao existe.")
        continue
    }
    $s = $t.Settings
    $s.StartWhenAvailable = $true
    $s.DisallowStartIfOnBatteries = $false
    $s.StopIfGoingOnBatteries = $false
    $s.Enabled = $true
    $gats = @($t.Triggers | Where-Object { $_ })
    if (-not ($gats | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' })) {
        $b = New-ScheduledTaskTrigger -AtStartup
        $b.Delay = 'PT2M'
        $gats += $b
    }
    try {
        Set-ScheduledTask -TaskName $n -Trigger $gats -Settings $s -ErrorAction Stop | Out-Null
        $info = Get-ScheduledTaskInfo -TaskName $n -ErrorAction SilentlyContinue
        Dizer ("  ok: $n roda tambem 2 min depois de ligar o PC; ultima vez " + $info.LastRunTime + ', resultado ' + $info.LastTaskResult)
    } catch {
        Dizer "  FALHOU ajustar $n : $($_.Exception.Message)"
        $falta.Add("Ajustar a tarefa $n : ver o erro no relatorio.")
    }
}
if (Get-ScheduledTask -TaskName 'AnvisaSNGPC_Login' -ErrorAction SilentlyContinue) {
    Dizer '  AnvisaSNGPC_Login precisa da conta aberta: o item 3 garante.'
}

# Sem o Firebird o Digifarma nao tem banco, e nem a ponte nem o agente
# leem nada. So mexo no que esta Manual: Desativado pode ser de proposito
# - banco em outra maquina.
$fbs = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'firebird' -or $_.DisplayName -match 'firebird' })
if ($fbs.Count -eq 0) { Dizer '  Firebird: nenhum servico neste PC - o banco deve estar em outra maquina.' }
foreach ($f in $fbs) {
    if ($f.StartMode -eq 'Manual') {
        Set-Service -Name $f.Name -StartupType Automatic -ErrorAction SilentlyContinue
        # recuperacao so em quem eu mudei: a de quem ja era Automatico fica
        sc.exe failure $f.Name reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
        Dizer "  ok: $($f.DisplayName) passou de Manual para Automatico"
    } else { Dizer "  $($f.DisplayName): $($f.StartMode), $($f.State)" }
    if ($f.StartMode -ne 'Disabled' -and $f.State -ne 'Running') {
        Start-Service -Name $f.Name -ErrorAction SilentlyContinue
        Dizer "  liguei $($f.DisplayName), que estava parado"
    }
}

# ------------------------------------------------------------------
Secao 'O que fica para uma pessoa'
$falta.Add('FALTA DE LUZ: so a BIOS liga o PC sozinho quando a energia volta. Na BIOS/UEFI, procure "Restore on AC Power Loss" ou "AC Power Recovery" e ponha em "Power On". Um nobreak evita o desligamento.')
$i = 1
foreach ($f in $falta) { Dizer ("  $i. " + $f); $i++ }

Secao 'Para desfazer'
Dizer '  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 0 /f'
Dizer "  schtasks /Delete /TN $VIGIA /F"
Dizer '  powercfg /hibernate on'
Dizer '  reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /f'

Gravar
