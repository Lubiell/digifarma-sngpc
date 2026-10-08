<#
.SYNOPSIS
Desmarca "Psicotrópico" (controlado) e "Antimicrobiano" no cadastro de produtos do Digifarma (banco Firebird).

.DESCRIPTION
Sem -Aplicar, só simula: mostra os produtos marcados (com estoque) e grava a lista em CSV. Nada é alterado.
Com -Escolher, abre a lista para escolher quais produtos desmarcar; com -Codigos, desmarca só os códigos informados.
Com -Estoque ComEstoque, mostra só os produtos com saldo em estoque.
Com -Aplicar: faz backup do banco (gbak), grava a lista e um script para desfazer, e desmarca numa única transação.
Com -Desfazer <desfazer.sql>: remarca o que uma execução anterior desmarcou.
Usa o isql e o gbak que vêm com o Firebird; não instala nada.
Leia o README.md desta pasta antes de usar (há implicações no SNGPC).

.EXAMPLE
.\desmarcar-controlados.ps1 -Banco 'localhost:C:\Digifarma\Digifarma6.FDB' -Descobrir
.\desmarcar-controlados.ps1 -Banco 'localhost:C:\Digifarma\Digifarma6.FDB' -Estoque ComEstoque -Escolher
.\desmarcar-controlados.ps1 -Banco 'localhost:C:\Digifarma\Digifarma6.FDB' -Estoque ComEstoque -Escolher -Aplicar
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Banco,
    [string]$Usuario = 'SYSDBA',
    [switch]$Descobrir,
    [string]$Tabela,
    [string]$CampoPsicotropico,
    [string]$CampoAntimicrobiano,
    [ValidateSet('Ambos', 'Psicotropico', 'Antimicrobiano')][string]$Desmarcar = 'Ambos',
    [string]$ValorMarcado,
    [string]$ValorDesmarcado,
    [ValidateSet('Todos', 'ComEstoque', 'SemEstoque')][string]$Estoque = 'Todos',
    [string]$CampoEstoque,
    [string]$CampoDescricao,
    [string]$TabelaEstoque,
    [string]$ChaveEstoque,
    [switch]$Escolher,
    [string[]]$Codigos,
    [switch]$Aplicar,
    [switch]$SemPerguntar,
    [ValidateRange(1, 10)][int]$Tentativas = 3,
    [string]$Desfazer,
    [switch]$SemBackup,
    [string]$Isql,
    [string]$PastaSaida
)
$ErrorActionPreference = 'Stop'

$Utf8Bom = New-Object Text.UTF8Encoding $true
$Utf8Estrito = New-Object Text.UTF8Encoding $false, $true
$Ansi = [Text.Encoding]::GetEncoding(1252)
$TiposNumero = @(7, 8, 16)            # SMALLINT, INTEGER, BIGINT
$TiposTexto = @(14, 37)               # CHAR, VARCHAR
$TipoBoolean = 23
$TiposQtd = @(7, 8, 16, 10, 27)       # inteiros, NUMERIC/DECIMAL, FLOAT, DOUBLE
$NomesTipo = @{ 7 = 'SMALLINT'; 8 = 'INTEGER'; 16 = 'BIGINT'; 14 = 'CHAR'; 37 = 'VARCHAR'; 23 = 'BOOLEAN' }
# Pares (marcado, desmarcado) reconhecidos sozinhos; outros valores exigem -ValorMarcado/-ValorDesmarcado.
$ParesTexto = @(@('S', 'N'), @('T', 'F'), @('Y', 'N'), @('V', 'F'), @('1', '0'), @('s', 'n'))
$ParesNumero = @(@('1', '0'), @('-1', '0'))
# Colunas de estoque que não são o saldo (mínimo, máximo, datas, valores).
$NaoESaldo = 'MIN|MAX|IDEAL|SEGUR|REPOS|PEDID|ULT|DATA|DT_|VALOR|VLR|CUSTO|PRECO'
$EsperaTrava = 5       # segundos que cada produto espera se estiver em uso em outro computador
$PausaTentativa = 10   # segundos entre uma tentativa e outra para os produtos que ficaram em uso
$script:LogFile = $null
$script:Senha = $null

function Write-Log([string]$Msg) {
    Write-Host $Msg
    if ($script:LogFile) {
        [IO.File]::AppendAllText($script:LogFile, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Msg + [Environment]::NewLine, $Utf8Bom)
    }
}

function Stop-Script([string]$Msg, [int]$Codigo = 1) {
    Write-Log "ERRO: $Msg"
    exit $Codigo
}

# Aspas no estilo da linha de comando do Windows (o caminho do banco pode ter espaços).
function Format-Arg([string]$A) {
    if ($A -notmatch '[\s"]') { return $A }
    return '"' + ($A -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Convert-Bytes([byte[]]$Bytes) {
    try { return $Utf8Estrito.GetString($Bytes) } catch { return $Ansi.GetString($Bytes) }
}

# Roda isql/gbak sem janela; a senha vai por ISC_PASSWORD só para o processo filho, nunca na linha de comando.
function Start-Tool([string]$Exe, [string[]]$Argumentos) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($Argumentos | ForEach-Object { Format-Arg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($script:Senha) { $psi.EnvironmentVariables['ISC_PASSWORD'] = $script:Senha }
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = New-Object IO.MemoryStream
    $err = New-Object IO.MemoryStream
    $t1 = $p.StandardOutput.BaseStream.CopyToAsync($out)
    $t2 = $p.StandardError.BaseStream.CopyToAsync($err)
    $p.WaitForExit()
    $t1.Wait(); $t2.Wait()
    return [pscustomobject]@{ Codigo = $p.ExitCode; Saida = (Convert-Bytes $out.ToArray()); Erro = (Convert-Bytes $err.ToArray()) }
}

# Executa SQL pelo isql (-b: para no primeiro erro e não faz commit) e devolve as linhas da saída.
function Invoke-Isql([string]$Sql, [switch]$PodeFalhar) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmp, "SET HEADING OFF;`n$Sql`n", $Ansi)
        $r = Start-Tool $script:IsqlExe @('-b', '-q', '-ch', 'NONE', '-user', $Usuario, '-i', $tmp, $Banco)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    # "Rolling back work." sai ao fechar a transação padrão do isql depois do COMMIT; não é erro.
    $msg = (($r.Erro -split "`r?`n") | Where-Object { $_.Trim() -and $_.Trim() -ne 'Rolling back work.' }) -join "`n"
    if ($r.Codigo -ne 0 -or $msg) {
        if ($msg -match 'lock conflict|deadlock|concurrent update') { $msg += "`nAlgum computador está usando estes produtos; rode de novo em instantes." }
        if ($PodeFalhar) { Write-Log "ERRO: o isql falhou (código $($r.Codigo)): $msg"; return $null }
        Stop-Script "o isql falhou (código $($r.Codigo)): $msg"
    }
    return $r.Saida -split "`r?`n"
}

# Linhas marcadas com '#<tag>|' viram vetores de campos; o resto da saída do isql é ignorado.
# Número de campos diferente (código com '|' ou quebra de linha) desalinharia a chave: para tudo.
function Get-Rows($Linhas, [string]$Tag, [int]$Campos) {
    $prefixo = "#$Tag|"
    foreach ($l in $Linhas) {
        $l = $l.Trim()
        if (-not $l.StartsWith($prefixo, [StringComparison]::Ordinal)) { continue }
        $r = $l.Substring($prefixo.Length).Split('|')
        if ($r.Count -ne $Campos) {
            Stop-Script "resposta inesperada do banco (esperava $Campos campos, vieram $($r.Count)): $l`nAlgum código ou nome tem '|' ou quebra de linha; o programa parou antes de alterar."
        }
        , $r
    }
}

function Format-Equals([string]$Coluna, [string]$Literal) {
    if ($Literal -eq 'NULL') { return "$Coluna IS NULL" }
    return "$Coluna = $Literal"
}

# Estoque como o isql mostra (10.000, 1.5E+01) -> 10, 15.
function Format-Number([string]$S) {
    $d = 0.0
    if ([double]::TryParse($S, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        try { return ([decimal]$d).ToString([Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    return $S
}

# Identificador SQL: nome comum vai como está; o resto entre aspas.
function Q([string]$Nome) {
    if ($Nome -cmatch '^[A-Z][A-Z0-9_$]*$') { return $Nome }
    return '"' + $Nome.Replace('"', '""') + '"'
}

# Literal SQL conforme o tipo da coluna.
function L($Col, [string]$V) {
    if ($Col.Tipo -eq $TipoBoolean) {
        if ($V -notmatch '^(TRUE|FALSE)$') { Stop-Script "$($Col.Campo) é BOOLEAN; use TRUE ou FALSE, não '$V'." }
        return $V.ToUpper()
    }
    if ($TiposNumero -contains $Col.Tipo) {
        if ($V -notmatch '^-?\d+$') { Stop-Script "$($Col.Campo) é numérico; '$V' não é número." }
        return $V
    }
    return "'" + $V.Replace("'", "''") + "'"
}

function Get-Kind([string]$Campo) {
    if ($Campo -match 'PSICO|CONTROLAD') { return 'Psicotropico' }
    if ($Campo -match 'ANTIMIC|ANTIBIO') { return 'Antimicrobiano' }
    if ($Campo -match 'TERAPEUT|SNGPC|PORTARIA') { return 'Outro' }
    return $null
}

function Test-FlagType($Col) {
    if ($Col.Calculado) { return $false }
    if ($Col.Tipo -eq $TipoBoolean -or $TiposTexto -contains $Col.Tipo) { return $true }
    return ($TiposNumero -contains $Col.Tipo -and $Col.Escala -eq 0)
}

function Find-Isql {
    if ($Isql) {
        if (-not (Test-Path -LiteralPath $Isql -PathType Leaf)) { Stop-Script "isql não encontrado em '$Isql'." }
        return (Resolve-Path -LiteralPath $Isql).Path
    }
    $cmd = Get-Command 'isql.exe', 'isql-fb' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($padrao in @('Firebird\*\isql.exe', 'Firebird\*\bin\isql.exe')) {
            $achado = Get-ChildItem -Path (Join-Path $base $padrao) -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
            if ($achado) { return $achado.FullName }
        }
    }
    Stop-Script "isql do Firebird não encontrado. Informe o caminho com -Isql 'C:\...\isql.exe' (fica na pasta do Firebird instalado no servidor do Digifarma)."
}

function Format-Values($Col) {
    if (-not $Col.Valores) { return '(tabela vazia)' }
    $txt = ($Col.Valores | ForEach-Object { if ($_.Nulo) { "(vazio)=$($_.Qtd)" } else { "'$($_.Valor)'=$($_.Qtd)" } }) -join '  '
    if (@($Col.Valores).Count -ge 20) { $txt += '  ... (muitos valores: não parece caixa de marcar)' }
    return $txt
}

# Distribuição de valores de cada coluna (no máximo 20 valores distintos por coluna).
function Add-Values($Cols) {
    $Cols = @($Cols)
    if (-not $Cols) { return }
    $sql = for ($i = 0; $i -lt $Cols.Count; $i++) {
        $c = Q $Cols[$i].Campo
        "SELECT FIRST 20 '#V|$i|' || CASE WHEN $c IS NULL THEN '1' ELSE '0' END || '|' || COALESCE(REPLACE(TRIM(CAST($c AS VARCHAR(100))), '|', '/'), '') || '|' || CAST(COUNT(*) AS VARCHAR(20)) FROM $(Q $Cols[$i].Tabela) GROUP BY $c;"
    }
    $linhas = Invoke-Isql ($sql -join "`n")
    foreach ($c in $Cols) { $c.Valores = @() }
    foreach ($r in @(Get-Rows $linhas 'V' 4)) {
        $Cols[[int]$r[0]].Valores += [pscustomobject]@{ Nulo = ($r[1] -eq '1'); Valor = $r[2]; Qtd = [long]$r[3] }
    }
}

# Descobre o par (marcado, desmarcado) pelos valores que existem na coluna; só aceita se os dois existirem.
# Devolve: literal SQL marcado, literal SQL desmarcado (pode ser NULL), texto do valor marcado como o isql o mostra.
function Resolve-Pair($Col) {
    if ($ValorMarcado) {
        $par = @($ValorMarcado, $ValorDesmarcado)
    } else {
        # Atribuição em cada ramo: um if usado como expressão desmontaria o par único do BOOLEAN.
        if ($Col.Tipo -eq $TipoBoolean) { $pares = @(, @('TRUE', 'FALSE')) } elseif ($TiposNumero -contains $Col.Tipo) { $pares = $ParesNumero } else { $pares = $ParesTexto }
        $vals = @($Col.Valores | Where-Object { -not $_.Nulo } | ForEach-Object { $_.Valor })
        $servem = @($pares | Where-Object { $p = $_; -not @($vals | Where-Object { $p -cnotcontains $_ }) })
        $par = @($servem | Where-Object { $vals -ccontains $_[0] }) + $servem | Select-Object -First 1
        if (-not $par) {
            Stop-Script ("não sei qual valor significa 'marcado' em $($Col.Tabela).$($Col.Campo). Valores encontrados: $(Format-Values $Col)`n" +
                "Rode com -Descobrir e informe -ValorMarcado e -ValorDesmarcado.") 2
        }
        if ($vals -ccontains $par[0] -and $vals -cnotcontains $par[1]) {
            Stop-Script ("em $($Col.Tabela).$($Col.Campo) há produtos com '$($par[0])', mas nenhum com '$($par[1])'. Valores: $(Format-Values $Col)`n" +
                "Veja no Digifarma como fica um produto desmarcado e informe -ValorMarcado $($par[0]) -ValorDesmarcado <valor> (NULL se ficar vazio).") 2
        }
    }
    $m = L $Col $par[0]
    $d = if ($par[1] -eq 'NULL') { 'NULL' } else { L $Col $par[1] }
    $texto = if ($Col.Tipo -eq $TipoBoolean) { $m } elseif ($TiposNumero -contains $Col.Tipo) { [string][long]$par[0] } else { $par[0] }
    return @($m, $d, $texto)
}

# Escolhe tabela e colunas: as informadas ou, se não houver dúvida, as encontradas pelo nome.
function Resolve-Target($Colunas) {
    $precisa = @()
    if ($Desmarcar -ne 'Antimicrobiano') { $precisa += 'Psicotropico' }
    if ($Desmarcar -ne 'Psicotropico') { $precisa += 'Antimicrobiano' }
    $explicito = @{ Psicotropico = $CampoPsicotropico; Antimicrobiano = $CampoAntimicrobiano }
    $cands = @($Colunas | Where-Object { $precisa -contains $_.Kind -and (Test-FlagType $_) })

    $tab = $Tabela
    if (-not $tab) {
        $todas = @($cands | ForEach-Object { $_.Tabela } | Sort-Object -Unique)
        $tabs = @($todas | Where-Object { $_ -match 'PROD' })
        if ($todas.Count -eq 0) { return @{ Erro = 'nenhuma coluna com PSICO, CONTROLAD, ANTIMIC ou ANTIBIO no nome.' } }
        if ($tabs.Count -eq 0) { return @{ Erro = "as colunas estão em $($todas -join ', '), sem PROD no nome; informe -Tabela com a tabela do cadastro de produtos." } }
        if ($tabs.Count -gt 1) { return @{ Erro = "mais de uma tabela possível ($($tabs -join ', ')); informe -Tabela." } }
        $tab = $tabs[0]
    }
    $doTab = @($Colunas | Where-Object { $_.Tabela -eq $tab })
    if (-not $doTab) { return @{ Erro = "tabela '$tab' não existe no banco." } }

    $alvos = @()
    foreach ($k in $precisa) {
        if ($explicito[$k]) {
            $col = @($doTab | Where-Object { $_.Campo -eq $explicito[$k] })
            if (-not $col) { return @{ Erro = "coluna '$($explicito[$k])' não existe em $tab." } }
            if (-not (Test-FlagType $col[0])) { return @{ Erro = "coluna $tab.$($col[0].Campo) não é de marcar (tipo $($col[0].Tipo))." } }
        } else {
            $col = @($cands | Where-Object { $_.Tabela -eq $tab -and $_.Kind -eq $k })
            $param = if ($k -eq 'Psicotropico') { '-CampoPsicotropico' } else { '-CampoAntimicrobiano' }
            if ($col.Count -eq 0) { return @{ Erro = "nenhuma coluna de $k em $tab; informe $param ou use -Desmarcar." } }
            if ($col.Count -gt 1) { return @{ Erro = "mais de uma coluna de $k em $tab ($(($col | ForEach-Object { $_.Campo }) -join ', ')); informe $param." } }
        }
        $alvos += [pscustomobject]@{ Kind = $k; Col = $col[0] }
    }
    $pk = @($Chaves | Where-Object { $_[0] -eq $doTab[0].Tabela } | ForEach-Object { $nome = $_[1]; $doTab | Where-Object { $_.Campo -eq $nome } })
    return @{ Erro = $null; Tabela = $doTab[0].Tabela; Alvos = $alvos; Colunas = $doTab; Pk = $pk }
}

# Saldo de estoque: coluna na própria tabela de produtos ou soma numa tabela de estoque (por loja, lote...).
# Devolve a expressão SQL (tabela de produtos com apelido P) e a descrição, ou o motivo de não achar.
function Resolve-Stock($Alvo) {
    $saldo = { $TiposQtd -contains $_.Tipo -and $_.Campo -notmatch $NaoESaldo }
    if (-not $TabelaEstoque) {
        if ($CampoEstoque) {
            $col = @($Alvo.Colunas | Where-Object { $_.Campo -eq $CampoEstoque })
            if (-not $col) { return @{ Erro = "coluna '$CampoEstoque' não existe em $($Alvo.Tabela)." } }
        } else {
            $col = @($Alvo.Colunas | Where-Object $saldo | Where-Object { $_.Campo -match 'ESTOQUE|SALDO' })
            if ($col.Count -eq 0) { return @{ Erro = "nenhuma coluna de estoque em $($Alvo.Tabela); informe -CampoEstoque ou -TabelaEstoque." } }
            if ($col.Count -gt 1) { return @{ Erro = "mais de uma coluna de estoque em $($Alvo.Tabela) ($(($col | ForEach-Object { $_.Campo }) -join ', ')); informe -CampoEstoque." } }
        }
        if ($TiposQtd -notcontains $col[0].Tipo) { return @{ Erro = "coluna $($Alvo.Tabela).$($col[0].Campo) não é numérica." } }
        return @{ Erro = $null; Expr = "COALESCE(P.$(Q $col[0].Campo), 0)"; Texto = "$($Alvo.Tabela).$($col[0].Campo)" }
    }
    if ($Alvo.Pk.Count -ne 1) { return @{ Erro = "estoque em outra tabela exige chave primária de uma coluna em $($Alvo.Tabela)." } }
    if (-not $CampoEstoque -or -not $ChaveEstoque) { return @{ Erro = 'com -TabelaEstoque, informe também -CampoEstoque (o saldo) e -ChaveEstoque (a coluna que aponta para o produto).' } }
    $doTab = @($Colunas | Where-Object { $_.Tabela -eq $TabelaEstoque })
    if (-not $doTab) { return @{ Erro = "tabela '$TabelaEstoque' não existe no banco." } }
    $tab = $doTab[0].Tabela
    $col = @($doTab | Where-Object { $_.Campo -eq $CampoEstoque })
    if (-not $col) { return @{ Erro = "coluna '$CampoEstoque' não existe em $tab." } }
    if ($TiposQtd -notcontains $col[0].Tipo) { return @{ Erro = "coluna $tab.$($col[0].Campo) não é numérica." } }
    $nomePk = $Alvo.Pk[0].Campo
    $chave = @($doTab | Where-Object { $_.Campo -eq $ChaveEstoque })
    if (-not $chave) { return @{ Erro = "coluna '$ChaveEstoque' não existe em $tab." } }
    $expr = "(SELECT COALESCE(SUM(E.$(Q $col[0].Campo)), 0) FROM $(Q $tab) E WHERE E.$(Q $chave[0].Campo) = P.$(Q $nomePk))"
    return @{ Erro = $null; Expr = $expr; Texto = "soma de $tab.$($col[0].Campo) por $($chave[0].Campo)" }
}

# "1,3,5-8" -> 1,3,5,6,7,8 (dentro de 1..Max); $null se algo não for válido.
function ConvertFrom-Ranges([string]$Texto, [int]$Max) {
    $nums = New-Object Collections.Generic.List[int]
    foreach ($t in ($Texto -split '[,;\s]+' | Where-Object { $_ })) {
        if ($t -match '^(\d{1,6})(-(\d{1,6}))?$') {
            $a = [int]$Matches[1]
            $b = if ($Matches[3]) { [int]$Matches[3] } else { $a }
            if ($a -lt 1 -or $b -gt $Max -or $a -gt $b) { return $null }
            foreach ($n in $a..$b) { $nums.Add($n) }
        } else { return $null }
    }
    if ($nums.Count -eq 0) { return $null }
    return @($nums | Sort-Object -Unique)
}

function Format-Row($R) {
    $partes = @($R.Chave -join '/') + @($R.Descricao)
    if ($script:TemEstoque) { $partes += $R.Estoque }
    return ($partes + $R.Flags) -join ' | '
}

function Get-Header {
    $partes = @((@($alvo.Pk | ForEach-Object { $_.Campo })) -join '/') + @('Descrição')
    if ($script:TemEstoque) { $partes += 'Estoque' }
    return ($partes + @($alvo.Alvos | ForEach-Object { $_.Col.Campo })) -join ' | '
}

# Lista para o usuário escolher: janela (Out-GridView) no Windows PowerShell; senão, menu numerado no console.
function Select-Products($Lista) {
    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        try {
            $itens = for ($i = 0; $i -lt $Lista.Count; $i++) {
                $o = [ordered]@{ Item = $i + 1; Codigo = ($Lista[$i].Chave -join '/'); Descricao = $Lista[$i].Descricao }
                if ($script:TemEstoque) {
                    $o['Estoque'] = $Lista[$i].Estoque
                    try { $o['Estoque'] = [decimal]::Parse($Lista[$i].Estoque, [Globalization.CultureInfo]::InvariantCulture) } catch { }
                }
                for ($k = 0; $k -lt $alvo.Alvos.Count; $k++) { $o[$alvo.Alvos[$k].Col.Campo] = $Lista[$i].Flags[$k] }
                [pscustomobject]$o
            }
            $titulo = if ($Aplicar) {
                'DESMARCAR: clique nos produtos (Ctrl+clique para vários, Shift+clique para uma sequência) e depois em OK. Em seguida confirme na janela preta.'
            } else {
                'SIMULAÇÃO (não altera nada): clique nos produtos (Ctrl+clique para vários) e em OK. Para desmarcar de verdade, use a opção 2 do menu.'
            }
            $esc = @($itens | Out-GridView -Title $titulo -PassThru)
            return @($esc | ForEach-Object { $Lista[$_.Item - 1] })
        } catch {
            Write-Host "Janela de seleção indisponível ($($_.Exception.Message)); usando a lista no console."
        }
    }
    Write-Host ''
    Write-Host ('  Item  ' + (Get-Header))
    for ($i = 0; $i -lt $Lista.Count; $i++) { Write-Host ('  {0,4}  {1}' -f ($i + 1), (Format-Row $Lista[$i])) }
    while ($true) {
        $resp = "$(Read-Host 'Itens a desmarcar (ex.: 1,3,5-8), T para todos, Enter para cancelar')".Trim()
        if (-not $resp) { return @() }
        if ($resp -match '^(t|todos)$') { return $Lista }
        $idx = ConvertFrom-Ranges $resp $Lista.Count
        if ($idx) { return @($idx | ForEach-Object { $Lista[$_ - 1] }) }
        Write-Host "Não entendi. Use os números da coluna Item (1 a $($Lista.Count)), separados por vírgula, ou faixas como 5-8."
    }
}

# ---------- validação dos parâmetros ----------
foreach ($n in @($Tabela, $CampoPsicotropico, $CampoAntimicrobiano, $CampoEstoque, $TabelaEstoque, $ChaveEstoque, $CampoDescricao)) {
    if ($n -and $n -notmatch '^[A-Za-z_][A-Za-z0-9_$]*$') { Stop-Script "nome inválido: '$n'." }
}
foreach ($v in @($ValorMarcado, $ValorDesmarcado)) {
    if ($v -and $v -notmatch '^-?[A-Za-z0-9]{1,20}$') { Stop-Script "valor inválido: '$v' (use letras ou números, ex.: S, N, 1, 0)." }
}
if ([bool]$ValorMarcado -ne [bool]$ValorDesmarcado) { Stop-Script 'informe -ValorMarcado e -ValorDesmarcado juntos.' }
if ($ValorMarcado -and $ValorMarcado -ceq $ValorDesmarcado) { Stop-Script '-ValorMarcado e -ValorDesmarcado não podem ser iguais.' }
if ($ValorMarcado -eq 'NULL') { Stop-Script '-ValorMarcado não pode ser NULL (só -ValorDesmarcado).' }
if (($CampoPsicotropico -or $CampoAntimicrobiano) -and -not $Tabela) { Stop-Script 'ao informar a coluna, informe também -Tabela.' }
if ($ChaveEstoque -and -not $TabelaEstoque) { Stop-Script '-ChaveEstoque só vale junto com -TabelaEstoque.' }
if ($Escolher -and $Codigos) { Stop-Script 'use -Escolher ou -Codigos, não os dois.' }
$Codigos = @($Codigos | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })

$script:IsqlExe = Find-Isql
if (-not $env:ISC_PASSWORD) {
    $seg = Read-Host -AsSecureString "Senha do usuário $Usuario do Firebird"
    $script:Senha = (New-Object Management.Automation.PSCredential('u', $seg)).GetNetworkCredential().Password
}

# ---------- modo -Desfazer ----------
if ($Desfazer) {
    if (-not (Test-Path -LiteralPath $Desfazer -PathType Leaf)) { Stop-Script "arquivo '$Desfazer' não encontrado." }
    $conteudo = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Desfazer).Path, $Ansi)
    if (-not $conteudo.StartsWith('/* Remarca os produtos desmarcados')) { Stop-Script "'$Desfazer' não é um desfazer.sql gerado por este programa." }
    Write-Host "Rodando $Desfazer em $Banco ..."
    Invoke-Isql $conteudo | Out-Null
    Write-Host 'Pronto: os produtos desmarcados por aquela execução voltaram a ficar marcados (os que ainda estavam desmarcados).'
    exit 0
}

# ---------- estrutura do banco ----------
Write-Host "Lendo a estrutura do banco $Banco ..."
$linhas = Invoke-Isql @'
SELECT '#M|' || TRIM(rf.RDB$RELATION_NAME) || '|' || TRIM(rf.RDB$FIELD_NAME) || '|' || CAST(f.RDB$FIELD_TYPE AS VARCHAR(5)) || '|' ||
       CAST(COALESCE(f.RDB$FIELD_SCALE, 0) AS VARCHAR(5)) || '|' || CASE WHEN f.RDB$COMPUTED_BLR IS NULL THEN '0' ELSE '1' END
FROM RDB$RELATION_FIELDS rf
JOIN RDB$RELATIONS r ON r.RDB$RELATION_NAME = rf.RDB$RELATION_NAME
JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE
WHERE COALESCE(r.RDB$SYSTEM_FLAG, 0) = 0 AND r.RDB$VIEW_BLR IS NULL
ORDER BY rf.RDB$RELATION_NAME, rf.RDB$FIELD_POSITION;
SELECT '#K|' || TRIM(c.RDB$RELATION_NAME) || '|' || TRIM(s.RDB$FIELD_NAME)
FROM RDB$RELATION_CONSTRAINTS c
JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = c.RDB$INDEX_NAME
WHERE c.RDB$CONSTRAINT_TYPE = 'PRIMARY KEY'
ORDER BY c.RDB$RELATION_NAME, s.RDB$FIELD_POSITION;
'@
$Colunas = @(Get-Rows $linhas 'M' 5 | ForEach-Object {
        [pscustomobject]@{ Tabela = $_[0]; Campo = $_[1]; Tipo = [int]$_[2]; Escala = [int]$_[3]; Calculado = ($_[4] -eq '1'); Kind = (Get-Kind $_[1]); Valores = @() }
    })
$Chaves = @(Get-Rows $linhas 'K' 2)
if (-not $Colunas) { Stop-Script 'o banco não tem tabelas de usuário. Confira o caminho em -Banco.' }

# ---------- modo -Descobrir ----------
if ($Descobrir) {
    $cands = @($Colunas | Where-Object { $_.Kind -and (Test-FlagType $_) })
    if (-not $cands) {
        Write-Host 'Nenhuma coluna com PSICO, CONTROLAD, ANTIMIC, ANTIBIO, TERAPEUT, SNGPC ou PORTARIA no nome.'
        Write-Host 'Tabelas com PROD no nome e suas colunas:'
        $Colunas | Where-Object { $_.Tabela -match 'PROD' } | Group-Object Tabela | ForEach-Object {
            Write-Host "  $($_.Name): $(($_.Group | ForEach-Object { $_.Campo }) -join ', ')"
        }
        exit 2
    }
    # Valores só das colunas de marcar: as outras (SNGPC, classe terapêutica) podem ter CPF, nomes etc.
    $mostrar = @($cands | Where-Object { $_.Kind -ne 'Outro' -and $_.Campo -notmatch 'CPF|CNPJ|NOME|RG|FONE|EMAIL|ENDERECO' })
    Write-Host "Contando os valores de $($mostrar.Count) coluna(s) (pode demorar em tabelas grandes) ..."
    Add-Values $mostrar
    Write-Host ''
    Write-Host 'Colunas candidatas (tabela.coluna  tipo  provável  valores=quantidade):'
    foreach ($c in $cands) {
        Write-Host ("  {0}.{1}  {2}  {3}" -f $c.Tabela, $c.Campo, $NomesTipo[$c.Tipo], $c.Kind)
        if ($mostrar -contains $c) { Write-Host ("      {0}" -f (Format-Values $c)) } else { Write-Host '      (valores não exibidos)' }
    }
    Write-Host ''
    Write-Host 'Colunas de estoque possíveis:'
    $Colunas | Where-Object { $_.Tabela -match 'ESTOQ|LOTE|SALDO' -or ($_.Tabela -match 'PROD' -and $TiposQtd -contains $_.Tipo -and $_.Campo -match 'ESTOQUE|SALDO') } |
        Group-Object Tabela | ForEach-Object { Write-Host "  $($_.Name): $(($_.Group | ForEach-Object { $_.Campo }) -join ', ')" }
    Write-Host ''
    $alvo = Resolve-Target $Colunas
    if ($alvo.Erro) {
        Write-Host "Escolha automática: não foi possível, $($alvo.Erro)"
        Write-Host 'Informe -Tabela e -CampoPsicotropico / -CampoAntimicrobiano conforme a lista acima.'
    } else {
        Write-Host "Escolha automática: $($alvo.Tabela) -> $(($alvo.Alvos | ForEach-Object { "$($_.Kind): $($_.Col.Campo)" }) -join '; ')"
        $est = Resolve-Stock $alvo
        if ($est.Erro) { Write-Host "Estoque: não identificado, $($est.Erro)" } else { Write-Host "Estoque: $($est.Texto)" }
        Write-Host 'Confira se são mesmo as caixas e o estoque da tela de cadastro de produtos antes de usar -Aplicar.'
    }
    exit 0
}

# ---------- simulação / aplicação ----------
$alvo = Resolve-Target $Colunas
if ($alvo.Erro) { Stop-Script "$($alvo.Erro) Rode com -Descobrir para ver as colunas candidatas." 2 }
$T = $alvo.Tabela
$pk = $alvo.Pk
if (($Escolher -or $Codigos) -and -not $pk) { Stop-Script "$T não tem chave primária; não dá para escolher produtos. Rode sem -Escolher/-Codigos." }
if ($Codigos -and $pk.Count -ne 1) { Stop-Script "-Codigos exige chave primária de uma coluna em $T; use -Escolher." }
Add-Values ($alvo.Alvos | ForEach-Object { $_.Col })
foreach ($a in $alvo.Alvos) {
    $par = Resolve-Pair $a.Col
    $a | Add-Member -NotePropertyName Marcado -NotePropertyValue $par[0]
    $a | Add-Member -NotePropertyName Desmarcado -NotePropertyValue $par[1]
    $a | Add-Member -NotePropertyName TextoMarcado -NotePropertyValue $par[2]
}
$est = Resolve-Stock $alvo
if ($est.Erro -and ($Estoque -ne 'Todos' -or $CampoEstoque -or $TabelaEstoque)) { Stop-Script "estoque: $($est.Erro) Rode com -Descobrir para ver as colunas de estoque." 2 }
$script:TemEstoque = -not $est.Erro

if (-not $PastaSaida) { $PastaSaida = Join-Path (Join-Path $PSScriptRoot 'registros') (Get-Date -Format 'yyyyMMdd-HHmmss') }
New-Item -ItemType Directory -Force $PastaSaida | Out-Null
$PastaSaida = (Resolve-Path -LiteralPath $PastaSaida).Path
$script:LogFile = Join-Path $PastaSaida 'log.txt'
Write-Log "Banco: $Banco | usuário: $Usuario | modo: $(if ($Aplicar) { 'APLICAR' } else { 'simulação' })"
foreach ($a in $alvo.Alvos) {
    Write-Log "  $($a.Kind): $T.$($a.Col.Campo) de $($a.Marcado) para $($a.Desmarcado)  [valores hoje: $(Format-Values $a.Col)]"
}
if ($script:TemEstoque) { Write-Log "  Estoque: $($est.Texto) | filtro: $Estoque" } else { Write-Log "  Estoque: não exibido ($($est.Erro))" }

function Get-Counts {
    $sql = for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) {
        $a = $alvo.Alvos[$i]
        "SELECT '#C|$i|' || CAST(COUNT(*) AS VARCHAR(20)) FROM $(Q $T) WHERE $(Q $a.Col.Campo) = $($a.Marcado);"
    }
    $r = @(Get-Rows (Invoke-Isql ($sql -join "`n")) 'C' 2)
    return @($r | Sort-Object { [int]$_[0] } | ForEach-Object { [long]$_[1] })
}
$antes = Get-Counts
for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) { Write-Log "  Marcados como $($alvo.Alvos[$i].Kind) (todos): $($antes[$i])" }

# Lista dos produtos marcados (com o filtro de estoque): chave, descrição, estoque e valores atuais.
$textos = @($alvo.Colunas | Where-Object { $TiposTexto -contains $_.Tipo })
$desc = $null
if ($CampoDescricao) {
    $desc = $textos | Where-Object { $_.Campo -eq $CampoDescricao } | Select-Object -First 1
    if (-not $desc) { Stop-Script "não há coluna de texto '$CampoDescricao' em $T. Colunas de texto: $(($textos | ForEach-Object { $_.Campo }) -join ', ')" }
} else {
    # No Digifarma as colunas de PRODUTOS começam com PROD_ (PROD_SALDO): PROD_NOME, PROD_DESC...
    $padroes = @('^(PROD_?)?DESCRICAO$', '^(PROD_?)?NOME$', '^(PROD_?)?DESCR$', '^(PROD_?)?DESC$',
        '^DESCRICAO_?PRODUTO$', '^NOME_?PRODUTO$', 'DESCRICAO', 'DESCRI', '^NOME', 'NOME$', '^PRODUTO$')
    foreach ($padrao in $padroes) {
        $desc = $textos | Where-Object { $_.Campo -match $padrao } | Select-Object -First 1
        if ($desc) { break }
    }
}
if ($desc) {
    Write-Log "  Descrição: $T.$($desc.Campo)"
} else {
    Write-Log "  Descrição: não encontrada. Informe -CampoDescricao com uma destas colunas de texto: $(($textos | ForEach-Object { $_.Campo }) -join ', ')"
}
$expr = @($pk | ForEach-Object { "COALESCE(CAST(P.$(Q $_.Campo) AS VARCHAR(100)), '')" })
$expr += if ($desc) {
    "COALESCE(REPLACE(REPLACE(REPLACE(SUBSTRING(P.$(Q $desc.Campo) FROM 1 FOR 100), '|', '/'), ASCII_CHAR(13), ' '), ASCII_CHAR(10), ' '), '')"
} else { "''" }
$expr += if ($script:TemEstoque) { "CAST($($est.Expr) AS VARCHAR(40))" } else { "''" }
$expr += @($alvo.Alvos | ForEach-Object { "COALESCE(CAST(P.$(Q $_.Col.Campo) AS VARCHAR(20)), '')" })
$where = '(' + (($alvo.Alvos | ForEach-Object { "P.$(Q $_.Col.Campo) = $($_.Marcado)" }) -join ' OR ') + ')'
if ($Estoque -eq 'ComEstoque') { $where += " AND $($est.Expr) > 0" }
if ($Estoque -eq 'SemEstoque') { $where += " AND $($est.Expr) <= 0" }
$ordem = if ($pk) { ($pk | ForEach-Object { "P.$(Q $_.Campo)" }) -join ', ' } else { '1' }
$n = $pk.Count
$lista = @(Get-Rows (Invoke-Isql "SELECT '#L|' || $($expr -join " || '|' || ") FROM $(Q $T) P WHERE $where ORDER BY $ordem;") 'L' ($n + 2 + $alvo.Alvos.Count) | ForEach-Object {
        $campos = @($_ | ForEach-Object { $_.TrimEnd() })
        $chave = @()
        if ($n) { $chave = @($campos[0..($n - 1)]) }
        [pscustomobject]@{
            Chave     = $chave
            Descricao = $campos[$n]
            Estoque   = (Format-Number $campos[$n + 1])
            Flags     = @($campos[($n + 2)..($campos.Count - 1)])
        }
    })
$filtroTxt = @{ Todos = ''; ComEstoque = ' com estoque'; SemEstoque = ' sem estoque' }[$Estoque]
Write-Log "  Produtos marcados$($filtroTxt): $($lista.Count)"

# Escolha: todos da lista, os códigos informados ou os que o usuário marcar.
if ($Codigos) {
    $sel = @($lista | Where-Object { $Codigos -contains $_.Chave[0] })
    $achados = @($sel | ForEach-Object { $_.Chave[0] })
    $faltam = @($Codigos | Where-Object { $achados -notcontains $_ })
    if ($faltam) { Write-Log "  Códigos fora da lista de marcados$($filtroTxt) (ignorados): $($faltam -join ', ')" }
} elseif ($Escolher -and $lista.Count) {
    $sel = @(Select-Products $lista)
} else {
    $sel = $lista
}
if ($Codigos -or $Escolher) { Write-Log "  Escolhidos: $($sel.Count)" }

$csv = Join-Path $PastaSaida 'produtos-a-desmarcar.csv'
$cab = @($pk | ForEach-Object { $_.Campo }) + @($(if ($desc) { $desc.Campo } else { 'DESCRICAO' }))
if ($script:TemEstoque) { $cab += 'ESTOQUE' }
$cab += @($alvo.Alvos | ForEach-Object { $_.Col.Campo })
$linhasCsv = New-Object Collections.Generic.List[string]
foreach ($campos in @(, $cab) + @($sel | ForEach-Object { , (@($_.Chave) + @($_.Descricao) + $(if ($script:TemEstoque) { @($_.Estoque) } else { @() }) + $_.Flags) })) {
    $linhasCsv.Add((($campos | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ';'))
}
[IO.File]::WriteAllLines($csv, $linhasCsv, $Utf8Bom)
Write-Log "  Lista ($($sel.Count) produto(s), valores de antes): $csv"
if (-not $Escolher -and $sel.Count) {
    Write-Host ('    ' + (Get-Header))
    $sel | Select-Object -First 20 | ForEach-Object { Write-Host ('    ' + (Format-Row $_)) }
    if ($sel.Count -gt 20) { Write-Host "    ... e mais $($sel.Count - 20) (veja o CSV)" }
}

# Quantas marcações cada coluna vai perder.
$esperado = @(for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) { $k = $i; @($sel | Where-Object { $_.Flags[$k] -ceq $alvo.Alvos[$k].TextoMarcado }).Count })
$total = ($esperado | Measure-Object -Sum).Sum
if ($total -eq 0) { Write-Log 'Nenhuma marcação a desfazer. Nada foi alterado.'; exit 0 }
if (-not $Aplicar) {
    Write-Log "SIMULAÇÃO: nada foi alterado. Seriam desmarcadas $total marcação(ões) em $($sel.Count) produto(s)."
    if (($Escolher -or $Codigos) -and $pk.Count -eq 1 -and $sel.Count -le 200) {
        Write-Log "  Para aplicar exatamente esta escolha, rode de novo com: -Aplicar -Codigos $(($sel | ForEach-Object { $_.Chave[0] }) -join ',')"
    } else {
        Write-Log '  Confira a lista e, para desmarcar, rode de novo com -Aplicar (e os mesmos filtros).'
    }
    exit 0
}

Write-Host ''
Write-Host 'ATENÇÃO: produto que já foi enviado ao SNGPC como controlado/antimicrobiano e for desmarcado'
Write-Host 'gera divergência na ANVISA (veja o README). Pode deixar o Digifarma aberto, mas ninguém deve'
Write-Host 'estar com o cadastro destes produtos aberto: ao salvar, o Digifarma pode gravar a marcação de volta.'
if (-not $SemPerguntar) {
    $resp = Read-Host "Digite DESMARCAR para alterar $total marcação(ões) em $($sel.Count) produto(s) de $T"
    if ($resp -cne 'DESMARCAR') { Write-Log 'Cancelado pelo usuário. Nada foi alterado.'; exit 1 }
}

if ($SemBackup) {
    Write-Log 'Backup NÃO feito (-SemBackup).'
} else {
    $gbak = Join-Path (Split-Path $script:IsqlExe) ('gbak' + [IO.Path]::GetExtension($script:IsqlExe))
    if (-not (Test-Path -LiteralPath $gbak)) { Stop-Script "gbak não encontrado em $gbak. Faça o backup pelo Digifarma e rode com -SemBackup." }
    $fbk = Join-Path $PastaSaida 'backup-antes.fbk'
    Write-Log "Fazendo backup em $fbk (pode demorar) ..."
    $r = Start-Tool $gbak @('-b', '-user', $Usuario, $Banco, $fbk)
    if ($r.Codigo -ne 0 -or -not (Test-Path -LiteralPath $fbk) -or (Get-Item -LiteralPath $fbk).Length -eq 0) {
        Stop-Script "o backup falhou; nada foi alterado. $($r.Erro.Trim())"
    }
    Write-Log "Backup ok ($([math]::Round((Get-Item -LiteralPath $fbk).Length / 1MB, 1)) MB)."
}

# Comandos de alteração: um por produto e coluna (com chave primária) ou um por coluna (sem chave).
$itens = New-Object Collections.Generic.List[object]
$volta = New-Object Collections.Generic.List[string]
if ($pk) {
    foreach ($row in $sel) {
        $cond = (@(for ($k = 0; $k -lt $n; $k++) { "$(Q $pk[$k].Campo) = $(L $pk[$k] $row.Chave[$k])" })) -join ' AND '
        for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) {
            $a = $alvo.Alvos[$i]
            if ($row.Flags[$i] -cne $a.TextoMarcado) { continue }
            $c = Q $a.Col.Campo
            $itens.Add([pscustomobject]@{ Sql = "UPDATE $(Q $T) SET $c = $($a.Desmarcado) WHERE $cond AND $c = $($a.Marcado);"; Codigo = ($row.Chave -join '/') })
            $volta.Add("UPDATE $(Q $T) SET $c = $($a.Marcado) WHERE $cond AND $(Format-Equals $c $a.Desmarcado);")
        }
    }
}
if ($volta.Count) {
    $desfazer = Join-Path $PastaSaida 'desfazer.sql'
    $volta.Insert(0, "/* Remarca os produtos desmarcados em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'). Banco: $Banco */")
    $volta.Insert(1, "/* Uso: .\desmarcar-controlados.ps1 -Banco <banco> -Desfazer desfazer.sql */")
    $volta.Add('COMMIT;')
    [IO.File]::WriteAllLines($desfazer, $volta, $Ansi)
    Write-Log "Script para desfazer: $desfazer"
} else {
    Write-Log "Sem chave primária em ${T}: não gerei desfazer.sql (use o backup para voltar)."
}

# Com o Digifarma aberto, um produto pode estar em uso (venda baixando estoque, cadastro sendo salvo):
# a transação espera até $EsperaTrava s por ele em vez de falhar na hora.
$Transacao = "SET TRANSACTION READ WRITE WAIT ISOLATION LEVEL READ COMMITTED LOCK TIMEOUT $EsperaTrava"

if (-not $pk) {
    $upd = foreach ($a in $alvo.Alvos) {
        $filtro = @{ Todos = ''; ComEstoque = " AND $($est.Expr) > 0"; SemEstoque = " AND $($est.Expr) <= 0" }[$Estoque]
        "UPDATE $(Q $T) P SET $(Q $a.Col.Campo) = $($a.Desmarcado) WHERE P.$(Q $a.Col.Campo) = $($a.Marcado)$filtro;"
    }
    $res = Invoke-Isql ("$Transacao;`n" + ($upd -join "`n") + "`nCOMMIT;") -PodeFalhar
    $depois = Get-Counts
    if ($null -eq $res) {
        if (-not @(for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) { if ($antes[$i] -ne $depois[$i]) { $i } })) {
            Stop-Script 'o banco desfez a transação inteira; nada foi alterado.'
        }
        Stop-Script "as contagens mudaram apesar do erro (antes: $($antes -join '/'); depois: $($depois -join '/')). Confira no Digifarma; para voltar, use o backup."
    }
    for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) {
        Write-Log "  $($alvo.Alvos[$i].Kind): $($antes[$i] - $depois[$i]) desmarcado(s) de $($esperado[$i]) previsto(s); ainda marcados (todos): $($depois[$i])"
    }
    Write-Log 'Concluído. Confira alguns produtos no Digifarma.'
    exit 0
}

# Com chave primária: blocos de produtos, cada um na sua transação. Produto que continua em uso depois
# da espera fica de fora sem desfazer os outros (WHEN ANY) e é tentado de novo nas próximas rodadas.
# Devolve quantas linhas foram alteradas e as posições (em $Lote) dos comandos que falharam.
function Invoke-Updates($Lote) {
    $sql = New-Object Text.StringBuilder
    [void]$sql.AppendLine('SET TERM ^ ;')
    $i = 0
    while ($i -lt $Lote.Count) {
        [void]$sql.AppendLine("$Transacao^")
        [void]$sql.AppendLine("EXECUTE BLOCK RETURNS (R VARCHAR(1000)) AS DECLARE N INTEGER = 0; DECLARE F VARCHAR(900) = ''; BEGIN")
        $inicio = $sql.Length
        while ($i -lt $Lote.Count -and ($sql.Length - $inicio) -lt 8000) {
            [void]$sql.AppendLine("BEGIN $($Lote[$i].Sql) N = N + ROW_COUNT; WHEN ANY DO F = F || '$i,'; END")
            $i++
        }
        [void]$sql.AppendLine("R = '#U|' || N || '|' || F; SUSPEND; END^")
        [void]$sql.AppendLine('COMMIT^')
    }
    [void]$sql.AppendLine('SET TERM ; ^')
    $res = Invoke-Isql $sql.ToString() -PodeFalhar
    if ($null -eq $res) { return $null }
    $ok = 0
    $falhas = @()
    foreach ($r in @(Get-Rows $res 'U' 2)) {
        $ok += [int]$r[0]
        $falhas += @($r[1].Split(',') | Where-Object { $_ } | ForEach-Object { [int]$_ })
    }
    return @{ Ok = $ok; Falhas = $falhas }
}

$pendentes = @(0..($itens.Count - 1))
$feitos = 0
# (o contador não pode se chamar $t: o PowerShell não diferencia maiúsculas e ele apagaria $T, a tabela)
for ($rodada = 1; $rodada -le $Tentativas -and $pendentes.Count; $rodada++) {
    if ($rodada -gt 1) {
        Write-Log "  $($pendentes.Count) marcação(ões) em produto em uso em outro computador; tentando de novo em $PausaTentativa s ($rodada de $Tentativas) ..."
        Start-Sleep -Seconds $PausaTentativa
    }
    $r = Invoke-Updates @($pendentes | ForEach-Object { $itens[$_] })
    if ($null -eq $r) {
        Stop-Script "a gravação parou no meio; o que já foi gravado continua gravado. Rode a simulação de novo para ver o que falta; para voltar, use -Desfazer $desfazer."
    }
    $feitos += $r.Ok
    $pendentes = @($r.Falhas | ForEach-Object { $pendentes[$_] })
}

$depois = Get-Counts
for ($i = 0; $i -lt $alvo.Alvos.Count; $i++) { Write-Log "  Ainda marcados como $($alvo.Alvos[$i].Kind) (todos): $($depois[$i])" }
Write-Log "  Desmarcadas: $feitos de $($itens.Count) marcação(ões) escolhida(s)."
$outros = $itens.Count - $feitos - $pendentes.Count
if ($outros -gt 0) { Write-Log "  $outros marcação(ões) já tinham sido mudadas por alguém no Digifarma durante a execução." }
$emUso = @($pendentes | ForEach-Object { $itens[$_].Codigo } | Sort-Object -Unique)
if ($emUso) {
    Write-Log "ATENÇÃO: $($emUso.Count) produto(s) continuaram em uso em outro computador e seguem marcados: $($emUso -join ', ')"
    if ($pk.Count -eq 1) { Write-Log "  Rode de novo mais tarde com: -Aplicar -Codigos $($emUso -join ',')" }
    exit 3
}
Write-Log 'Concluído. Se algum computador estiver com a tela de um destes produtos aberta, feche e abra de novo; confira alguns produtos no Digifarma.'
