param(
    [ValidateSet("up", "test", "down", "clean")]
    [string]$Action = "test",
    [string]$ProjectName = "pdp-fnd04",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeFile = Join-Path $repoRoot "infra\local\control-plane\docker-compose.yml"
$envFile = if ($EnvFile) { (Resolve-Path $EnvFile).Path } else { Join-Path $repoRoot ".env" }
$composeBase = @("--project-name", $ProjectName, "--env-file", $envFile, "-f", $composeFile)
$apiHostPort = 8000

if (-not (Test-Path $envFile)) {
    throw "Arquivo .env nao encontrado. Copie .env.example para .env e ajuste os valores locais."
}

$apiPortSetting = Get-Content $envFile | Where-Object { $_ -match '^\s*CONTROL_API_HOST_PORT\s*=' } | Select-Object -First 1
if ($apiPortSetting -and $apiPortSetting -match '=\s*(\d+)\s*$') {
    $apiHostPort = [int]$Matches[1]
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker compose @composeBase @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose falhou com codigo $LASTEXITCODE."
    }
}

function Wait-Http {
    param([string]$Uri)
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "Endpoint $Uri nao respondeu com HTTP 200 no tempo esperado."
}

function Start-ControlPlane {
    Invoke-Compose up --build --detach control-api
    Wait-Http "http://127.0.0.1:$apiHostPort/health/live"
    Wait-Http "http://127.0.0.1:$apiHostPort/health/ready"
}

switch ($Action) {
    "up" {
        Start-ControlPlane
        Write-Output "FND-04 Control Plane iniciado."
    }
    "test" {
        Start-ControlPlane
        Invoke-Compose run --rm control-migrate
        Invoke-Compose --profile test run --build --rm control-api-test
        Write-Output "FND-04 validacao concluida."
    }
    "down" {
        Invoke-Compose down --remove-orphans
        Write-Output "FND-04 containers removidos; volume persistente preservado."
    }
    "clean" {
        Invoke-Compose down --volumes --remove-orphans
        Write-Output "FND-04 containers e volume removidos."
    }
}
