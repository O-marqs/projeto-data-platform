param(
    [ValidateSet("up", "test", "down", "clean")]
    [string]$Action = "test",
    [string]$ProjectName = "pdp-fnd01",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeFile = Join-Path $repoRoot "infra\local\docker-compose.yml"
$envFile = if ($EnvFile) { (Resolve-Path $EnvFile).Path } else { Join-Path $repoRoot ".env" }
$projectName = $ProjectName
$composeBase = @("--project-name", $projectName, "--env-file", $envFile, "-f", $composeFile)

if (-not (Test-Path $envFile)) {
    throw "Arquivo .env nao encontrado. Copie .env.example para .env e ajuste as credenciais locais."
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker compose @composeBase @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose falhou com codigo $LASTEXITCODE."
    }
}

function Wait-Healthy {
    param([string]$Service)
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $containerId = (& docker compose @composeBase ps -q $Service | Select-Object -First 1).Trim()
        if ($containerId) {
            $health = (& docker inspect --format '{{.State.Health.Status}}' $containerId 2>$null).Trim()
            if ($health -eq "healthy") {
                return
            }
        }
        Start-Sleep -Seconds 2
    }
    Invoke-Compose ps
    throw "Servico $Service nao ficou healthy no tempo esperado."
}

function Wait-Completed {
    param([string]$Service)
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $containerId = (& docker compose @composeBase ps -a -q $Service | Select-Object -First 1).Trim()
        if ($containerId) {
            $status = (& docker inspect --format '{{.State.Status}}' $containerId).Trim()
            if ($status -eq "exited") {
                $exitCode = (& docker inspect --format '{{.State.ExitCode}}' $containerId).Trim()
                if ($exitCode -eq "0") {
                    return
                }
                Invoke-Compose logs $Service
                throw "Servico $Service terminou com codigo $exitCode."
            }
        }
        Start-Sleep -Seconds 2
    }
    throw "Servico $Service nao terminou no tempo esperado."
}

function Start-Lab {
    Invoke-Compose up --detach
    Wait-Healthy "rustfs"
    Wait-Healthy "postgres"
    Wait-Healthy "polaris"
    Wait-Completed "polaris-catalog-init"
}

function Run-Spark {
    param([string]$Mode)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & docker compose @composeBase --profile fnd01 run --rm spark --mode $Mode
        if ($LASTEXITCODE -eq 0) {
            return
        }
        if ($attempt -lt 3) {
            Write-Output "FND01_SPARK_RETRY=START attempt=$($attempt + 1)"
            Start-Sleep -Seconds 5
        }
    }
    throw "Spark falhou apos 3 tentativas."
}

function Verify-Storage {
    $listing = @(Invoke-Compose run --rm rustfs-bucket-init -c 'aws s3 ls --recursive s3://$RUSTFS_BUCKET')
    $objectNames = $listing | ForEach-Object { ($_ -split '\s+', 4)[3] } | Where-Object { $_ }
    $dataObjects = @($objectNames | Where-Object { $_ -match '^.+/data/.+\.parquet$' })
    $metadataObjects = @($objectNames | Where-Object { $_ -match '^.+/metadata/.+\.(metadata\.json|avro)$' })
    if ($dataObjects.Count -eq 0 -or $metadataObjects.Count -eq 0) {
        throw "RustFS nao contem os objetos Iceberg esperados (data Parquet e metadata Iceberg)."
    }
    $listing | ForEach-Object { Write-Output $_ }
    Write-Output "FND01_STORAGE=PASS data_parquet=$($dataObjects.Count) metadata=$($metadataObjects.Count)"
}

switch ($Action) {
    "up" {
        Start-Lab
        Write-Output "FND-01 ambiente iniciado."
    }
    "test" {
        $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $coldStartTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Lab
        $coldStartTimer.Stop()
        Write-Output "FND01_COLD_START_SECONDS=$([math]::Round($coldStartTimer.Elapsed.TotalSeconds, 1))"

        $smokeTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Run-Spark "write-read"
        Verify-Storage
        $smokeTimer.Stop()
        Write-Output "FND01_SMOKE_SECONDS=$([math]::Round($smokeTimer.Elapsed.TotalSeconds, 1))"

        Invoke-Compose stop
        Write-Output "FND-01 ambiente parado sem remover volumes."

        $restartTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Lab
        Run-Spark "verify"
        Verify-Storage
        $restartTimer.Stop()
        Write-Output "FND01_RESTART_VERIFY_SECONDS=$([math]::Round($restartTimer.Elapsed.TotalSeconds, 1))"
        Write-Output "FND01_RESTART=PASS"
        $totalTimer.Stop()
        Write-Output "FND01_TOTAL_SECONDS=$([math]::Round($totalTimer.Elapsed.TotalSeconds, 1))"
    }
    "down" {
        Invoke-Compose down
        Write-Output "FND-01 containers removidos; volumes persistentes preservados."
    }
    "clean" {
        Invoke-Compose down --volumes
        Write-Output "FND-01 containers e volumes removidos."
    }
}
