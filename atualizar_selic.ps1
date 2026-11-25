<#
    ATUALIZAÇÃO AUTOMÁTICA DA TAXA DE REFERÊNCIA (CDI.json e TMS.json)
    ------------------------------------------------------------------
    Consulta a Meta Selic definida pelo Copom no Banco Central (mesmos dados da página
    bcb.gov.br/controleinflacao/historicotaxasjuros; alternativa: SGS, série 432)
    e, se houver nova Meta Selic, atualiza "taxasReferencia" nos dois arquivos:
        - a faixa vigente (dataFinal = null) é encerrada no dia anterior ao início da nova;
        - é incluída uma nova faixa vigente com taxaAnual = Meta Selic - 0,10.
    Somente o trecho da faixa vigente é reescrito; o restante do arquivo fica idêntico
    (mesma estrutura, formatação e quebras de linha).

    Uso:
        powershell -ExecutionPolicy Bypass -File atualizar_selic.ps1           (atualiza)
        powershell -ExecutionPolicy Bypass -File atualizar_selic.ps1 -Testar   (só mostra o que faria)

    Parâmetros de teste: -Pasta (onde estão os JSON) e -DadosApi (arquivo JSON no formato da API).
#>
param(
    [switch]$Testar,
    [string]$Pasta = $PSScriptRoot,
    [string]$DadosApi = ""
)
$ErrorActionPreference = "Stop"
$Arquivos = @("CDI.json", "TMS.json")
$Spread = [decimal]0.10        # taxa de referência = Meta Selic - 0,10
$Log = Join-Path $Pasta "atualizar_selic.log"
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8SemBom = New-Object System.Text.UTF8Encoding($false)
# No GitHub Actions não há log nem backup locais: o registro fica na aba Actions
# e o histórico de commits do repositório guarda as versões anteriores.
$NoGitHub = $env:GITHUB_ACTIONS -eq "true"

function Registrar([string]$msg){
    $linha = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Output $linha
    if(-not $Testar -and -not $NoGitHub){ Add-Content -Path $Log -Value $linha -Encoding UTF8 }
    if($NoGitHub -and $env:GITHUB_STEP_SUMMARY){ Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "- $msg" -Encoding UTF8 }
}

# Faixa vigente: { "dataInicial": "...", "dataFinal": null, "taxaAnual": n, "dataFinalFormula": "..." }
$Padrao = '(?m)^(?<ind>[ \t]*)\{\s*"dataInicial":\s*"(?<ini>\d{4}-\d{2}-\d{2})",\s*"dataFinal":\s*null,\s*"taxaAnual":\s*(?<taxa>-?[\d.]+),\s*"dataFinalFormula":\s*"(?<form>(?:[^"\\]|\\.)*)"\s*\}'

function Ler-FaixaVigente([string]$texto, [string]$nome){
    $m = [regex]::Matches($texto, $Padrao)
    if($m.Count -ne 1){ throw "$nome : esperada 1 faixa vigente (dataFinal null), encontradas $($m.Count). Nada foi alterado." }
    return $m[0]
}

# ---- Fontes da Meta Selic (Banco Central)
#   1. Histórico das taxas de juros (mesmos dados da página bcb.gov.br/controleinflacao/historicotaxasjuros)
#   2. SGS, série 432 - Meta Selic definida pelo Copom (alternativa, caso a primeira falhe)
$UrlHistorico = "https://www.bcb.gov.br/api/servico/sitebcb/historicotaxasjuros"

function Resumir([string]$texto){
    $t = ($texto -replace "\s+", " ").Trim()
    if($t.Length -gt 200){ $t = $t.Substring(0, 200) + "..." }
    return "'" + $t + "'"
}

# Baixa o conteúdo (texto) de uma URL, com até 3 tentativas
function Baixar([string]$url){
    # O site do BCB às vezes devolve uma página HTML (instabilidade/bloqueio temporário) em vez do JSON:
    # isso também conta como falha e gera nova tentativa, com espera crescente.
    $esperas = @(20, 60, 120)
    $erro = ""
    for($t = 0; $t -le $esperas.Count; $t++){
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60 -UserAgent "Mozilla/5.0 (compatible; AtualizadorSelic/1.0)" `
                -Headers @{ Accept = "application/json"; "Accept-Language" = "pt-BR,pt;q=0.9" }
            $conteudo = [string]$r.Content
            if($conteudo.TrimStart().StartsWith("<")){
                $titulo = [regex]::Match($conteudo, "(?is)<title[^>]*>(.*?)</title>").Groups[1].Value.Trim()
                $titulo = if($titulo){ "título da página: '" + ($titulo -replace "\s+", " ") + "'" } else { Resumir $conteudo }
                throw "resposta em HTML em vez de JSON (HTTP $($r.StatusCode); $titulo)"
            }
            return $conteudo
        } catch {
            $erro = $_.Exception.Message
            if($t -lt $esperas.Count){ Start-Sleep -Seconds $esperas[$t] }
        }
    }
    throw $erro
}

function Data-Iso($valor){
    # "2026-11-05T03:00:00Z" (03:00 UTC = 00:00 em Brasília). O PowerShell 7 pode já converter para DateTime.
    if($valor -is [datetime]){ return $valor.ToUniversalTime().AddHours(-3).Date }
    return [datetime]::ParseExact(([string]$valor).Substring(0, 10), "yyyy-MM-dd", $Inv)
}

# Converte a resposta em períodos de vigência: [{ Inicio, Selic }], em ordem de data
function Ler-Periodos([string]$conteudo){
    try { $json = $conteudo | ConvertFrom-Json } catch { throw "resposta não é JSON: $(Resumir $conteudo)" }
    $itens = @()
    if($json -isnot [array] -and $json.PSObject.Properties["conteudo"]){
        # Histórico das taxas de juros: uma linha por reunião do Copom
        foreach($r in @($json.conteudo)){
            if($r.DataInicioVigencia -and $r.MetaSelic -ne $null){
                $itens += [pscustomobject]@{ Inicio = (Data-Iso $r.DataInicioVigencia); Selic = [decimal]::Parse(([string]$r.MetaSelic).Replace(",", "."), $Inv) }
            }
        }
    } else {
        # SGS: uma linha por dia
        $hoje = (Get-Date).Date
        foreach($r in @($json)){
            if($r.data -and $r.valor){
                $d = [datetime]::ParseExact([string]$r.data, "dd/MM/yyyy", $Inv)
                if($d -le $hoje){ $itens += [pscustomobject]@{ Inicio = $d; Selic = [decimal]::Parse(([string]$r.valor).Replace(",", "."), $Inv) } }
            }
        }
    }
    if($itens.Count -eq 0){ throw "formato inesperado: $(Resumir $conteudo)" }
    # Ordena e junta períodos seguidos com a mesma taxa
    $periodos = @()
    foreach($i in ($itens | Sort-Object Inicio)){
        if($periodos.Count -eq 0 -or $periodos[-1].Selic -ne $i.Selic){ $periodos += $i }
    }
    return ,$periodos
}

function Obter-Periodos(){
    if($DadosApi){ return @{ Periodos = (Ler-Periodos (Get-Content $DadosApi -Raw -Encoding UTF8)); Fonte = "arquivo de teste" } }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ini = (Get-Date).AddDays(-400).ToString("dd/MM/yyyy")
    $fim = (Get-Date).ToString("dd/MM/yyyy")
    $fontes = @(
        @{ Nome = "BCB histórico das taxas de juros"; Url = $UrlHistorico },
        @{ Nome = "BCB SGS série 432"; Url = "https://api.bcb.gov.br/dados/serie/bcdata.sgs.432/dados?formato=json&dataInicial=$ini&dataFinal=$fim" }
    )
    $falhas = @()
    foreach($f in $fontes){
        try { return @{ Periodos = (Ler-Periodos (Baixar $f.Url)); Fonte = $f.Nome } }
        catch { $falhas += "$($f.Nome): $($_.Exception.Message)" }
    }
    $script:BcbIndisponivel = $true
    throw ("Não foi possível obter a Meta Selic. " + ($falhas -join " | "))
}
$BcbIndisponivel = $false

try {
    # ---- 1. Meta Selic: períodos de vigência
    $obtido = Obter-Periodos
    $periodos = $obtido.Periodos
    $atual = $periodos[-1]

    # ---- 2. Atualiza cada arquivo
    $houveAlteracao = $false
    foreach($nome in $Arquivos){
        $caminho = Join-Path $Pasta $nome
        $texto = [System.IO.File]::ReadAllText($caminho, $Utf8SemBom)
        $nl = if($texto.Contains("`r`n")){ "`r`n" } else { "`n" }
        $original = $texto
        $aplicadas = @()

        foreach($p in $periodos){
            $m = Ler-FaixaVigente $texto $nome
            $iniVigente = [datetime]::ParseExact($m.Groups["ini"].Value, "yyyy-MM-dd", $Inv)
            $taxaVigente = [decimal]::Parse($m.Groups["taxa"].Value, $Inv)
            $novaTaxa = $p.Selic - $Spread
            if($p.Inicio -le $iniVigente -or $novaTaxa -eq $taxaVigente){ continue }

            $ind = $m.Groups["ind"].Value
            $fimAnterior = $p.Inicio.AddDays(-1).ToString("yyyy-MM-dd")
            $novoIni = $p.Inicio.ToString("yyyy-MM-dd")
            $taxaTxt = $novaTaxa.ToString("0.####", $Inv)
            $bloco = @(
                "$ind{",
                "$ind  `"dataInicial`": `"$($m.Groups["ini"].Value)`",",
                "$ind  `"dataFinal`": `"$fimAnterior`",",
                "$ind  `"taxaAnual`": $($m.Groups["taxa"].Value)",
                "$ind},",
                "$ind{",
                "$ind  `"dataInicial`": `"$novoIni`",",
                "$ind  `"dataFinal`": null,",
                "$ind  `"taxaAnual`": $taxaTxt,",
                "$ind  `"dataFinalFormula`": `"$($m.Groups["form"].Value)`"",
                "$ind}"
            ) -join $nl
            $texto = $texto.Substring(0, $m.Index) + $bloco + $texto.Substring($m.Index + $m.Length)
            $aplicadas += "nova faixa a partir de $novoIni = $taxaTxt% a.a. (Meta Selic $($p.Selic.ToString('0.00', $Inv))%); faixa anterior ($($m.Groups['taxa'].Value)%) encerrada em $fimAnterior"
        }

        if($texto -ne $original){
            $null = $texto | ConvertFrom-Json   # garante que o JSON continua válido antes de gravar
            $houveAlteracao = $true
            foreach($a in $aplicadas){ Registrar "$nome : $a" }
            if(-not $Testar){
                if(-not $NoGitHub){
                    $backup = Join-Path (Join-Path $Pasta "Backup") "selic"
                    New-Item -ItemType Directory -Force -Path $backup | Out-Null
                    Copy-Item $caminho (Join-Path $backup ("{0}_{1}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $nome))
                }
                [System.IO.File]::WriteAllText($caminho, $texto, $Utf8SemBom)
            }
        }
    }

    if(-not $houveAlteracao){
        Registrar ("Sem alteração. Meta Selic vigente: {0}% desde {1} (referência {2}% a.a.). Fonte: {3}." -f `
            $atual.Selic.ToString("0.00", $Inv), $atual.Inicio.ToString("dd/MM/yyyy"), ($atual.Selic - $Spread).ToString("0.####", $Inv), $obtido.Fonte)
    } elseif($Testar){
        Write-Output "(modo teste: nenhum arquivo foi gravado)"
    }
} catch {
    if($BcbIndisponivel -and $NoGitHub){
        # BCB fora do ar ou bloqueando o servidor do GitHub: nada é alterado e a próxima execução tenta de novo.
        Registrar "AVISO: Banco Central indisponível nesta execução; arquivos não alterados. A verificação será repetida na próxima execução. Detalhe: $($_.Exception.Message)"
        Write-Output "::warning title=Banco Central indisponível::Não foi possível consultar a Meta Selic nesta execução. Os arquivos não foram alterados."
        exit 0
    }
    Registrar "ERRO: $($_.Exception.Message)"
    exit 1
}
