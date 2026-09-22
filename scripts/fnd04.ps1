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
$normalComposeBase = @("--project-name", $ProjectName, "--env-file", $envFile, "-f", $composeFile)
$activeComposeBase = $normalComposeBase
$apiHostPort = 8000
$normalApiHostPort = 8000
$normalDbHostPort = 5433
$testProjectName = "$ProjectName-test"
$testApiHostPort = 8001
$testDbHostPort = 5434
$testEnvironmentNames = @(
    "CONTROL_APP_ENV",
    "CONTROL_API_HOST_PORT",
    "CONTROL_DB_HOST_PORT",
    "CONTROL_DB_NAME",
    "CONTROL_DB_USER",
    "CONTROL_DB_PASSWORD",
    "CONTROL_DATABASE_URL"
)
$previousTestEnvironment = @{}

if (-not (Test-Path $envFile)) {
    throw "Arquivo .env nao encontrado. Copie .env.example para .env e ajuste os valores locais."
}

$apiPortSetting = Get-Content $envFile | Where-Object { $_ -match '^\s*CONTROL_API_HOST_PORT\s*=' } | Select-Object -First 1
if ($apiPortSetting -and $apiPortSetting -match '=\s*(\d+)\s*$') {
    $apiHostPort = [int]$Matches[1]
}
$normalApiHostPort = $apiHostPort
$dbPortSetting = Get-Content $envFile | Where-Object { $_ -match '^\s*CONTROL_DB_HOST_PORT\s*=' } | Select-Object -First 1
if ($dbPortSetting -and $dbPortSetting -match '=\s*(\d+)\s*$') {
    $normalDbHostPort = [int]$Matches[1]
}
$testApiHostPort = $normalApiHostPort + 1
$testDbHostPort = $normalDbHostPort + 1

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker compose @activeComposeBase @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose falhou com codigo $LASTEXITCODE."
    }
}

function Enter-TestEnvironment {
    $script:activeComposeBase = @("--project-name", $testProjectName, "--env-file", $envFile, "-f", $composeFile)
    $script:apiHostPort = $testApiHostPort

    foreach ($name in $testEnvironmentNames) {
        $previousTestEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }

    $env:CONTROL_APP_ENV = "test"
    $env:CONTROL_API_HOST_PORT = $testApiHostPort
    $env:CONTROL_DB_HOST_PORT = $testDbHostPort
    $env:CONTROL_DB_NAME = "control_test_db"
    $env:CONTROL_DB_USER = "control_test_user"
    $env:CONTROL_DB_PASSWORD = "change-me-control-test-password"
    $env:CONTROL_DATABASE_URL = "postgresql+psycopg://control_test_user:change-me-control-test-password@127.0.0.1:$testDbHostPort/control_test_db"
}

function Exit-TestEnvironment {
    foreach ($name in $testEnvironmentNames) {
        $previous = $previousTestEnvironment[$name]
        if ($null -eq $previous) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$name" $previous
        }
    }

    $script:activeComposeBase = $normalComposeBase
    $script:apiHostPort = $normalApiHostPort
}

function Assert-TestIsolation {
    if ($activeComposeBase[1] -ne $testProjectName) {
        throw "Teste bloqueado: projeto Compose de teste inesperado."
    }
    if ($env:CONTROL_APP_ENV -ne "test" -or $env:CONTROL_DB_NAME -ne "control_test_db") {
        throw "Teste bloqueado: ambiente ou database de teste nao esta isolado."
    }
    if ($env:CONTROL_API_HOST_PORT -ne "$testApiHostPort" -or $env:CONTROL_DB_HOST_PORT -ne "$testDbHostPort") {
        throw "Teste bloqueado: portas de teste inesperadas."
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
        Enter-TestEnvironment
        try {
            Assert-TestIsolation
            Invoke-Compose down --volumes --remove-orphans
            Start-ControlPlane
            Invoke-Compose run --rm control-migrate
            Invoke-Compose --profile test run --build --rm control-api-test
            Write-Output "FND-04 validacao concluida no ambiente descartavel $testProjectName."
        } finally {
            Assert-TestIsolation
            Invoke-Compose down --volumes --remove-orphans
            Exit-TestEnvironment
        }
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
