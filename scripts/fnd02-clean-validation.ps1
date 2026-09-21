param(
    [switch]$KeepVolumes
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 12)
$projectName = "pdp-fnd02-$suffix"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) $projectName
$envFile = Join-Path $tempDir ".env"
$composeFile = Join-Path $repoRoot "infra\local\docker-compose.yml"

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $envContent = Get-Content (Join-Path $repoRoot ".env.example") -Raw
    $envContent = $envContent.Replace("change-me-rustfs-secret", "fnd02-rustfs-$suffix")
    $envContent = $envContent.Replace("change-me-polaris-secret", "fnd02-polaris-$suffix")
    $envContent = $envContent.Replace("change-me-postgres-password", "fnd02-postgres-$suffix")
    $envContent += "`r`nFND01_RUSTFS_VOLUME_NAME=pdp_fnd02_${suffix}_rustfs_data`r`n"
    $envContent += "FND01_POSTGRES_VOLUME_NAME=pdp_fnd02_${suffix}_postgres_data`r`n"
    Set-Content -Path $envFile -Value $envContent -NoNewline

    & (Join-Path $repoRoot "scripts\fnd01.ps1") -Action test -ProjectName $projectName -EnvFile $envFile
    if ($LASTEXITCODE -ne 0) {
        throw "FND-02 clean validation failed with code $LASTEXITCODE."
    }
    Write-Output "FND02_CLEAN_INSTALL=PASS project=$projectName"
}
finally {
    $composeBase = @("--project-name", $projectName, "--env-file", $envFile, "-f", $composeFile)
    if (-not $KeepVolumes) {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & docker compose @composeBase down --volumes --remove-orphans *> $null
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (Test-Path $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
