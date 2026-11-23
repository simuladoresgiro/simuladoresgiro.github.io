<#
    ATUALIZAÇÃO AUTOMÁTICA DA TAXA DE REFERÊNCIA (CDI.json e TMS.json)
    ------------------------------------------------------------------
    Consulta a Meta Selic definida pelo Copom na API oficial do Banco Central
    (SGS, série 432 — mesma informação de bcb.gov.br/controleinflacao/historicotaxasjuros)
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

try {
    # ---- 1. Meta Selic (série 432) dos últimos 400 dias
    if($DadosApi){
        $serie = Get-Content $DadosApi -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ini = (Get-Date).AddDays(-400).ToString("dd/MM/yyyy")
        $fim = (Get-Date).ToString("dd/MM/yyyy")
        $url = "https://api.bcb.gov.br/dados/serie/bcdata.sgs.432/dados?formato=json&dataInicial=$ini&dataFinal=$fim"
        $serie = $null
        for($t = 1; $t -le 3 -and -not $serie; $t++){
            try { $serie = Invoke-RestMethod -Uri $url -TimeoutSec 60 } catch { if($t -eq 3){ throw } ; Start-Sleep -Seconds 20 }
        }
    }
    if(-not $serie -or $serie.Count -eq 0){ throw "API do Banco Central não retornou dados." }

    # Períodos de vigência: cada mudança de valor inicia um novo período
    $periodos = @()
    $anterior = $null
    foreach($item in $serie){
        $valor = [decimal]::Parse(([string]$item.valor).Replace(",", "."), $Inv)
        if($anterior -eq $null -or $valor -ne $anterior){
            $periodos += [pscustomobject]@{ Inicio = [datetime]::ParseExact($item.data, "dd/MM/yyyy", $Inv); Selic = $valor }
            $anterior = $valor
        }
    }
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
        Registrar ("Sem alteração. Meta Selic vigente: {0}% desde {1} (referência {2}% a.a.)." -f `
            $atual.Selic.ToString("0.00", $Inv), $atual.Inicio.ToString("dd/MM/yyyy"), ($atual.Selic - $Spread).ToString("0.####", $Inv))
    } elseif($Testar){
        Write-Output "(modo teste: nenhum arquivo foi gravado)"
    }
} catch {
    Registrar "ERRO: $($_.Exception.Message)"
    exit 1
}
