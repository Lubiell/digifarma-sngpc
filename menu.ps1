# Menu do FARMACIA - SNGPC, executado direto do GitHub.
#
# Nada fica no PC: cada ferramenta e baixada na hora para a pasta do
# agente, roda e e apagada em seguida. O .bat precisa estar em disco
# por um instante porque o Windows nao executa .bat da memoria.
#
# Uso, sem baixar nada antes:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12';iwr -UseBasicParsing https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main/menu.ps1 | iex"

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$CRU = 'https://raw.githubusercontent.com/Lubiell/digifarma-sngpc/main'

# As copias de backup ficam de fora: atualizar uma delas daria "deu certo"
# sem o servidor mudar nada. A Lixeira tambem, que ja enganou uma vez.
$FORA = 'SALVAR_FARMACIA|RECUPERAR_FARMACIA|PEGAR_APPJS|BACKUP_FARMACIA|\$RECYCLE'

function Achar-Agente {
    $aqui = Join-Path (Get-Location).Path 'agente_auto.py'
    if (Test-Path $aqui) { return (Get-Location).Path }
    $achadas = @()
    foreach ($d in @('C:','D:','E:','F:')) {
        if (-not (Test-Path "$d\")) { continue }
        foreach ($f in Get-ChildItem -Path "$d\" -Filter 'agente_auto.py' -Recurse -Force -ErrorAction SilentlyContinue) {
            if ($f.DirectoryName -match $FORA) { continue }
            $achadas += $f.DirectoryName
        }
    }
    $achadas = @($achadas | Sort-Object -Unique)
    if ($achadas.Count -eq 1) { return $achadas[0] }
    if ($achadas.Count -eq 0) {
        Write-Host 'Nao achei o agente_auto.py em disco nenhum.'
        Write-Host 'Rode a opcao de instalar, ou abra esta janela dentro da pasta do agente.'
        return $null
    }
    Write-Host 'Achei mais de uma pasta com agente_auto.py:'
    $achadas | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Abra o PowerShell dentro da pasta certa e rode de novo: estando nela, nao procura.'
    return $null
}

function Rodar-Bat([string]$Nome, [string]$Pasta, [string]$Destino) {
    $alvo = Join-Path $Destino $Nome
    Write-Host ''
    Write-Host "  baixando $Nome ..."
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$CRU/$Pasta/$Nome" -OutFile $alvo
    } catch {
        Write-Host "  nao consegui baixar: $($_.Exception.Message)"
        Write-Host '  Nada foi alterado.'
        return
    }
    if (-not (Select-String -Path $alvo -Pattern '@echo off' -Quiet)) {
        Write-Host '  o arquivo baixado nao parece um .bat. Nada foi alterado.'
        Remove-Item $alvo -Force -ErrorAction SilentlyContinue
        return
    }
    Write-Host '  ok'
    Write-Host ''
    try {
        & cmd.exe /c "`"$alvo`""
    } finally {
        Remove-Item $alvo -Force -ErrorAction SilentlyContinue
    }
}

function Limpar-Bats([string]$Destino) {
    $bats = @(Get-ChildItem -Path $Destino -Filter '*.bat' -ErrorAction SilentlyContinue)
    if (-not $bats) { Write-Host '  Nenhum .bat nesta pasta. Ja esta limpo.'; return }
    Write-Host '  Estes .bat serao apagados da pasta do agente:'
    $bats | ForEach-Object { Write-Host "    $($_.Name)" }
    Write-Host '  Eles vivem no repositorio e sao baixados na hora de usar.'
    $r = Read-Host '  Digite APAGAR para confirmar'
    if ($r -cne 'APAGAR') { Write-Host '  Cancelado. Nada foi apagado.'; return }
    foreach ($b in $bats) { Remove-Item $b.FullName -Force -ErrorAction SilentlyContinue }
    Write-Host "  $($bats.Count) arquivo(s) apagado(s)."
}

function Criar-Atalho {
    $cmd = "-NoProfile -ExecutionPolicy Bypass -Command ""[Net.ServicePointManager]::SecurityProtocol='Tls12';iwr -UseBasicParsing $CRU/menu.ps1 | iex"""
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FARMACIA - SNGPC.lnk'
    $w = New-Object -ComObject WScript.Shell
    $a = $w.CreateShortcut($lnk)
    $a.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $a.Arguments = $cmd
    $a.WorkingDirectory = [Environment]::GetFolderPath('Desktop')
    $a.Description = 'Abre o menu do FARMACIA - SNGPC direto do GitHub'
    $a.Save()
    Write-Host "  Atalho criado: $lnk"
    Write-Host '  Ele nao guarda nada: busca o menu no GitHub toda vez.'
}

$pasta = Achar-Agente
if (-not $pasta) { Read-Host 'Enter para sair' | Out-Null; exit 1 }

while ($true) {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' FARMACIA - SNGPC'
    Write-Host '============================================================'
    Write-Host "  Pasta do agente: $pasta"
    Write-Host ''
    Write-Host '   1 - Consertar tudo (uma visita, tudo de uma vez)'
    Write-Host '   2 - Atualizar o agente agora'
    Write-Host '   3 - Rodar o servidor agora'
    Write-Host '   4 - Instalar a chave nova do Firebase'
    Write-Host '   5 - Acelerar a fila (precisa de administrador)'
    Write-Host '   6 - Diagnostico do Anvisa.exe'
    Write-Host '   7 - Limpar as sobras desta pasta'
    Write-Host '   8 - Desmarcar psicotropico/antimicrobiano no Digifarma'
    Write-Host '   9 - Instalar o agente nesta maquina'
    Write-Host '   L - Apagar os .bat que sobraram na pasta do agente'
    Write-Host '   A - Criar atalho na area de trabalho'
    Write-Host '   0 - Sair'
    Write-Host ''
    $op = (Read-Host '  Opcao').Trim().ToUpper()

    switch ($op) {
        '1' { Rodar-Bat 'CONSERTAR_TUDO.bat'      'agente' $pasta }
        '2' { Rodar-Bat 'ATUALIZAR_AGENTE.bat'    'agente' $pasta }
        '3' { Rodar-Bat 'SERVIDOR_AGORA.bat'      'agente' $pasta }
        '4' { Rodar-Bat 'INSTALAR_CHAVE.bat'      'agente' $pasta }
        '5' { Rodar-Bat 'ACELERAR_FILA.bat'       'agente' $pasta }
        '6' { Rodar-Bat 'DIAGNOSTICO_ANVISA.bat'  'agente' $pasta }
        '7' { Rodar-Bat 'LIMPAR.bat'              'agente' $pasta }
        '8' {
            Write-Host ''
            Write-Host '  ATENCAO: isto GRAVA no Digifarma. Produto ja transmitido ao'
            Write-Host '  SNGPC como controlado, se desmarcado, gera divergencia na'
            Write-Host '  ANVISA. O programa simula primeiro e faz backup antes.'
            $c = Read-Host '  Digite SIM para continuar'
            if ($c -ceq 'SIM') {
                $ps = Join-Path $pasta 'desmarcar-controlados.ps1'
                try {
                    Invoke-WebRequest -UseBasicParsing -Uri "$CRU/ferramentas/desmarcar-controlados.ps1" -OutFile $ps
                    Rodar-Bat 'desmarcar-controlados.bat' 'ferramentas' $pasta
                } catch {
                    Write-Host "  nao consegui baixar: $($_.Exception.Message)"
                } finally {
                    Remove-Item $ps -Force -ErrorAction SilentlyContinue
                }
            }
        }
        '9' { Rodar-Bat 'INSTALAR_AGENTE.bat'     'agente' $pasta }
        'L' { Limpar-Bats $pasta }
        'A' { Criar-Atalho }
        '0' { break }
        default { Write-Host '  Opcao nao reconhecida.' }
    }
    if ($op -eq '0') { break }
    Write-Host ''
    Read-Host '  Enter para voltar ao menu' | Out-Null
}
