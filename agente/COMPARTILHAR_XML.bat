@echo off
chcp 1252 >nul
title COMPARTILHAR O XML DO SNGPC COM O SERVIDOR
setlocal

REM  Roda UMA VEZ em cada computador que transmite o SNGPC e nao e o
REM  servidor: o caixa/balcao e o computador do farmaceutico. Precisa de
REM  administrador: clique com o botao direito e "Executar como
REM  administrador".
REM
REM  Para baixar e rodar, num CMD de administrador:
REM     curl -fL -o "%TEMP%\COMPARTILHAR_XML.bat" https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/agente/COMPARTILHAR_XML.bat
REM     "%TEMP%\COMPARTILHAR_XML.bat"
REM
REM  O que faz (spec docs/specs/2026-10-16-xml-dos-outros-computadores.md):
REM   - acha a pasta onde o Digifarma grava o SNGPC.XML deste computador;
REM   - cria o usuario local leitor_sngpc, com senha nova gerada aqui;
REM   - compartilha SO essa pasta, oculta, como SNGPC_XML$, SOMENTE
REM     LEITURA, so para esse usuario;
REM   - libera o compartilhamento no firewall SO para o IP do servidor;
REM   - mostra o nome deste computador e a senha, para digitar no app.
REM
REM  O que NUNCA faz: gravar, apagar ou mexer em XML; compartilhar outra
REM  pasta; dar acesso a outro usuario ou IP; guardar a senha em arquivo.
REM
REM  Para desfazer tudo: rode com /remover.

set "FARM_ARQ=%~f0"
set "FARM_ARG=%~1"

where powershell >nul 2>&1
if errorlevel 1 goto SEM_POWERSHELL

set "PSEXE=powershell"
if defined PROCESSOR_ARCHITEW6432 set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:FARM_ARQ); $m='#'+'== POWERSHELL =='; $i=$t.IndexOf($m); if ($i -lt 0) { exit 9 }; iex $t.Substring($i)"
if errorlevel 9 goto VEIO_QUEBRADO
goto FIM

:SEM_POWERSHELL
echo  PowerShell nao encontrado neste computador. Nada foi alterado.
goto FIM

:VEIO_QUEBRADO
echo  Este arquivo veio sem o bloco PowerShell do fim. Baixe de novo.
echo  Nada foi alterado.
goto FIM

:FIM
echo.
pause
endlocal
goto :eof

#== POWERSHELL ==
# Daqui para baixo o CMD nunca chega: o goto :eof acima encerra o .bat.

$ErrorActionPreference = 'Stop'
$usuario = 'leitor_sngpc'
$compart = 'SNGPC_XML$'
$regra = 'SNGPC XML - somente o servidor'
$chaveLista = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
$xmlDeEnvio = @('SNGPC.XML', 'MOVIMENTACAO.XML', 'sngpc.zip')

function Dizer([string]$t) { Write-Host $t }
function Linha { Dizer ('=' * 64) }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Dizer ' Precisa de administrador. Clique com o botao direito neste'
    Dizer ' arquivo e escolha "Executar como administrador". Nada foi alterado.'
    return
}

# So cmdlets aqui: no PowerShell 5.1, com Stop, o aviso que o net.exe manda
# para o stderr vira erro e abortaria a limpeza no meio.
function Tirar-Tudo {
    $antigo = Get-SmbShare -Name $compart -ErrorAction SilentlyContinue
    if ($antigo) {
        & icacls $antigo.Path /remove:g $usuario | Out-Null
        Remove-SmbShare -Name $compart -Force -ErrorAction SilentlyContinue
    }
    Get-NetFirewallRule -DisplayName $regra -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Remove-LocalUser -Name $usuario -ErrorAction SilentlyContinue
    if (Test-Path $chaveLista) { Remove-ItemProperty -Path $chaveLista -Name $usuario -ErrorAction SilentlyContinue }
}

if ($env:FARM_ARG -eq '/remover') {
    Tirar-Tudo
    Dizer ' Compartilhamento, usuario leitor_sngpc e regra do firewall removidos.'
    Dizer ' No app, tire este computador da lista: XML de outro computador,'
    Dizer (' nome {0} e senha em branco.' -f $env:COMPUTERNAME)
    return
}

Linha
Dizer ' COMPARTILHAR O XML DO SNGPC COM O SERVIDOR'
Linha

# 1. a pasta do SNGPC.XML deste computador
$pasta = $null
$padrao = 'C:\Digifarma\Aplicativos\VerificaXML'
foreach ($n in $xmlDeEnvio) { if (Test-Path (Join-Path $padrao $n)) { $pasta = $padrao; break } }
if (-not $pasta) {
    Dizer ' Procurando o SNGPC.XML do Digifarma neste computador...'
    $raizes = @('C:\Digifarma', 'D:\Digifarma', 'C:\DigiFarma') | Where-Object { Test-Path $_ }
    $achados = foreach ($r in $raizes) {
        Get-ChildItem -Path $r -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
            Where-Object { $xmlDeEnvio -contains $_.Name }
    }
    $maisNovo = $achados | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($maisNovo) { $pasta = $maisNovo.DirectoryName }
}
if (-not $pasta) {
    Dizer ' Nao achei o SNGPC.XML. Digite a pasta onde o Digifarma grava o XML'
    Dizer ' do SNGPC neste computador, ou deixe em branco para sair:'
    $pasta = (Read-Host ' Pasta').Trim('" ')
    if (-not $pasta -or -not (Test-Path $pasta -PathType Container)) {
        Dizer ' Pasta vazia ou inexistente. Nada foi alterado.'
        return
    }
}
Dizer (' Pasta do XML: {0}' -f $pasta)

# 2. o IP do servidor, o unico que vai poder ler
$ipServidor = (Read-Host ' IP do servidor [Enter = 192.168.100.8]').Trim()
if (-not $ipServidor) { $ipServidor = '192.168.100.8' }
if ($ipServidor -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Dizer ' IP invalido. Nada foi alterado.'
    return
}

# 3. senha nova, sem letra que confunde (l/1, O/0), em blocos de 5
$alfabeto = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
do {
    $bytes = New-Object byte[] 20
    $rng.GetBytes($bytes)
    $cru = -join ($bytes | ForEach-Object { $alfabeto[$_ % $alfabeto.Length] })
} until ($cru -cmatch '[a-z]' -and $cru -cmatch '[A-Z]' -and $cru -match '[0-9]')
$senha = ($cru.Substring(0, 5), $cru.Substring(5, 5), $cru.Substring(10, 5), $cru.Substring(15, 5)) -join '-'

try {
    Tirar-Tudo

    # 4. usuario so para isto: sem tela de login, senha que nao expira.
    #    New-LocalUser, nao "net user": com senha de mais de 14 letras o
    #    net user para e pergunta S/N.
    $segura = ConvertTo-SecureString $senha -AsPlainText -Force
    New-LocalUser -Name $usuario -Password $segura -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires -Description 'Leitura do XML do SNGPC pelo servidor' | Out-Null
    # fora do grupo Usuarios (SID fixo: o nome do grupo muda com o idioma)
    try { Remove-LocalGroupMember -SID 'S-1-5-32-545' -Member $usuario -ErrorAction Stop } catch { }
    if (-not (Test-Path $chaveLista)) { New-Item -Path $chaveLista -Force | Out-Null }
    New-ItemProperty -Path $chaveLista -Name $usuario -Value 0 -PropertyType DWord -Force | Out-Null

    # 5. so leitura, na pasta e no compartilhamento
    & icacls $pasta /grant ('{0}:(OI)(CI)RX' -f $usuario) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'nao consegui dar leitura na pasta' }
    New-SmbShare -Name $compart -Path $pasta -ReadAccess $usuario -Description 'XML do SNGPC, so leitura, para o servidor' | Out-Null

    # 6. servico de compartilhamento ligado e firewall so para o servidor
    Set-Service -Name LanmanServer -StartupType Automatic
    Start-Service -Name LanmanServer -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $regra -Direction Inbound -Protocol TCP -LocalPort 445 -RemoteAddress $ipServidor -Action Allow -Profile Any | Out-Null
} catch {
    Dizer (' Deu errado: {0}' -f $_.Exception.Message)
    Dizer ' Desfazendo o que foi feito...'
    Tirar-Tudo
    return
}

Dizer ''
Linha
Dizer ' PRONTO. No app, aba Servidor, botao "XML de outro computador":'
Dizer ''
Dizer ('    Nome:  {0}' -f $env:COMPUTERNAME)
Dizer ('    Senha: {0}' -f $senha)
Dizer ''
Dizer ' Anote agora: a senha nao fica guardada neste computador e nao'
Dizer ' aparece de novo. Perdeu? Rode este arquivo outra vez: ele gera'
Dizer ' outra senha e a antiga deixa de valer.'
Dizer ''
Dizer (' So o servidor ({0}) consegue ler, e so le.' -f $ipServidor)
Linha
