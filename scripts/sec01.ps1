param(
    [ValidateSet("test")]
    [string]$Action = "test",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envPath = if ($EnvFile) { (Resolve-Path $EnvFile).Path } else { Join-Path $repoRoot ".env" }
$vaultComposeFile = Join-Path $repoRoot "infra\local\vault\docker-compose.yml"
$controlComposeFile = Join-Path $repoRoot "infra\local\control-plane\docker-compose.yml"

if (-not (Test-Path $envPath)) {
    throw "Arquivo .env nao encontrado. Copie .env.example para .env e ajuste os valores locais."
}

$suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 10)
$vaultProject = "pdp-sec01-test-vault-$suffix"
$controlProject = "pdp-sec01-test-control-$suffix"
$vaultContainer = "$vaultProject-vault-1"
$vaultPort = 18201
$controlDbPort = 5541
$controlApiPort = 8011
$dbName = "sec01_control_test"
$dbUser = "sec01_control_test"
$dbPassword = "sec01-disposable-password"
$vaultVolume = "pdp-sec01-test-vault-$suffix-data"
$vaultNetwork = "pdp-sec01-test-vault-$suffix-network"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pdp-sec01-$suffix"
$credentialFile = Join-Path $tempRoot "workload.json"
$previousCredentialFile = Join-Path $tempRoot "previous-workload.json"
$caseFile = Join-Path $tempRoot "case.json"

$normalVolumes = @(
    "pdp-fnd04_control_postgres_data",
    "pdp_fnd01_postgres_data",
    "pdp_fnd01_rustfs_data"
)
$volumeSnapshots = @{}

function Invoke-Docker {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Comando Docker falhou com codigo $LASTEXITCODE."
    }
}

function Invoke-Compose {
    param(
        [string[]]$ComposeBase,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )
    & docker compose @ComposeBase @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose falhou com codigo $LASTEXITCODE."
    }
}

function Get-VolumeSnapshot {
    param([string]$Name)
    $json = & docker volume inspect $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    $item = $json | ConvertFrom-Json | Select-Object -First 1
    return [ordered]@{
        Name = $item.Name
        Driver = $item.Driver
        Mountpoint = $item.Mountpoint
        CreatedAt = $item.CreatedAt
        Labels = ($item.Labels | ConvertTo-Json -Compress)
    }
}

function Assert-VolumeSnapshot {
    param([string]$Name, [hashtable]$Before)
    $after = Get-VolumeSnapshot $Name
    if ($null -eq $after) {
        throw "Volume persistente $Name desapareceu durante o teste."
    }
    foreach ($key in $Before.Keys) {
        if ([string]$after[$key] -ne [string]$Before[$key]) {
            throw "Volume persistente $Name foi alterado no campo $key."
        }
    }
}

function Set-Sec01Environment {
    $env:CONTROL_APP_ENV = "test"
    $env:CONTROL_API_HOST_PORT = $controlApiPort
    $env:CONTROL_DB_HOST_PORT = $controlDbPort
    $env:CONTROL_DB_NAME = $dbName
    $env:CONTROL_DB_USER = $dbUser
    $env:CONTROL_DB_PASSWORD = $dbPassword
    $env:CONTROL_DATABASE_URL = "postgresql+psycopg://${dbUser}:${dbPassword}@127.0.0.1:$controlDbPort/$dbName"
    $env:VAULT_API_HOST_PORT = $vaultPort
    $env:VAULT_VOLUME_NAME = $vaultVolume
    $env:VAULT_NETWORK_NAME = $vaultNetwork
    $env:VAULT_ADDR = "http://host.docker.internal:18201"
    $env:VAULT_APPROLE_MOUNT = "approle"
    $env:VAULT_KV_MOUNT = "pdp"
}

function Invoke-VaultApi {
    param(
        [ValidateSet("GET", "POST", "PUT")][string]$Method,
        [string]$Path,
        [string]$Token = "",
        [hashtable]$Body = $null
    )
    $headers = @{}
    if ($Token) { $headers["X-Vault-Token"] = $Token }
    $params = @{
        Method = $Method
        Uri = "http://127.0.0.1:$vaultPort$Path"
        Headers = $headers
        ContentType = "application/json"
        ErrorAction = "Stop"
    }
    if ($null -ne $Body) { $params.Body = $Body | ConvertTo-Json -Depth 10 -Compress }
    try {
        return Invoke-RestMethod @params
    } catch {
        $statusCode = "transport"
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        throw "Vault API falhou para $Method $Path (HTTP $statusCode) sem registrar corpo, token ou valor secreto."
    }
}

function Wait-Vault {
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        try {
            $status = Invoke-VaultApi -Method GET -Path "/v1/sys/seal-status"
            if ($status.initialized -eq $false) { return }
            if ($null -ne $status.sealed) { return }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw "Vault nao respondeu no tempo esperado."
}

function Wait-VaultActive {
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$vaultPort/v1/sys/health" -TimeoutSec 3
            if ($response.StatusCode -eq 200) { return }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw "Vault nao ficou ativo depois do unseal."
}

function Wait-Database {
    $compose = @("--project-name", $controlProject, "--env-file", $envPath, "-f", $controlComposeFile)
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $running = & docker compose @compose ps --status running --services 2>$null
        if ($running -contains "control-db") {
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "Banco descartavel nao ficou disponivel."
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline
}

function Invoke-ControlSql {
    param([string]$Sql)
    $compose = @("--project-name", $controlProject, "--env-file", $envPath, "-f", $controlComposeFile)
    & docker compose @compose exec -T control-db psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "SQL de preparacao do teste falhou." }
}

function Invoke-IntegrationTest {
    param(
        [string]$Mode,
        [string]$CredentialPath = "",
        [string]$TestFilter = ""
    )
    if (-not $CredentialPath) { $CredentialPath = $credentialFile }
    $case = Get-Content -LiteralPath $caseFile -Raw | ConvertFrom-Json
    $case.mode = $Mode
    Write-JsonFile $caseFile $case
    $compose = @("--project-name", $controlProject, "--env-file", $envPath, "-f", $controlComposeFile)
    $runArguments = @(
        "run", "--no-deps", "--build", "--rm",
        "-v", "${CredentialPath}:/run/secrets/sec01-workload.json:ro",
        "-v", "${caseFile}:/run/secrets/sec01-case.json:ro",
        "control-api-test", "pytest", "-q", "tests/test_vault_integration.py"
    )
    if ($TestFilter) { $runArguments += @("-k", $TestFilter) }
    Invoke-Compose $compose @runArguments
}

function Invoke-FailureTest {
    param([string]$Mode, [string]$CredentialPath = "")
    if (-not $CredentialPath) { $CredentialPath = $credentialFile }
    $case = Get-Content -LiteralPath $caseFile -Raw | ConvertFrom-Json
    $case.mode = $Mode
    Write-JsonFile $caseFile $case
    $compose = @("--project-name", $controlProject, "--env-file", $envPath, "-f", $controlComposeFile)
    $runArguments = @(
        "run", "--no-deps", "--rm",
        "-v", "${CredentialPath}:/run/secrets/sec01-workload.json:ro",
        "-v", "${caseFile}:/run/secrets/sec01-case.json:ro",
        "control-api-test", "pytest", "-q", "tests/test_vault_integration.py", "-k", "failure"
    )
    Invoke-Compose $compose @runArguments
}

function Set-VaultSecret {
    param([string]$Token, [string]$Path, [string]$SecretRef, [string]$Value)
    Invoke-VaultApi -Method POST -Path "/v1/pdp/data/$Path" -Token $Token -Body @{ data = @{ secret_ref = $SecretRef; value = $Value } } | Out-Null
}

function Write-WorkloadCredential {
    param([string]$Token, [string]$RoleName, [string]$RoleId, [string]$DomainId, [string]$ConnectionId, [string]$WorkloadId)
    $secretMetadata = @{
        domain_id = $DomainId
        connection_id = $ConnectionId
        workload_id = $WorkloadId
    } | ConvertTo-Json -Compress
    $secretId = (Invoke-VaultApi -Method POST -Path "/v1/auth/approle/role/$RoleName/secret-id" -Token $Token -Body @{ metadata = $secretMetadata }).data.secret_id
    Write-JsonFile $credentialFile @{ role_id = $RoleId; secret_id = $secretId }
}

function Invoke-BackupRestoreRehearsal {
    param([string]$SourceToken, [string]$Path, [string]$ExpectedValue)
    $backupSuffix = ([guid]::NewGuid().ToString("N")).Substring(0, 8)
    $restoreProject = "pdp-sec01-restore-$backupSuffix"
    $restorePort = 18202
    $restoreVolume = "pdp-sec01-restore-$backupSuffix-data"
    $restoreNetwork = "pdp-sec01-restore-$backupSuffix-network"
    $restoreContainer = "$restoreProject-vault-1"
    $snapshot = Join-Path $tempRoot "raft-$backupSuffix.snap"
    $restoreCompose = @("--project-name", $restoreProject, "--env-file", $envPath, "-f", $vaultComposeFile)
    $savedPort = $script:vaultPort
    $savedVolume = $env:VAULT_VOLUME_NAME
    $savedNetwork = $env:VAULT_NETWORK_NAME
    $savedAddress = $env:VAULT_ADDR
    try {
        docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$SourceToken $vaultContainer vault operator raft snapshot save /tmp/sec01.snap | Out-Null
        docker cp "${vaultContainer}:/tmp/sec01.snap" $snapshot | Out-Null
        if (-not (Test-Path $snapshot)) { throw "Snapshot Raft nao foi criado fora do repositorio." }

        $env:VAULT_API_HOST_PORT = $restorePort
        $env:VAULT_VOLUME_NAME = $restoreVolume
        $env:VAULT_NETWORK_NAME = $restoreNetwork
        $env:VAULT_ADDR = "http://host.docker.internal:$restorePort"
        $script:vaultPort = $restorePort
        Invoke-Compose $restoreCompose up --detach vault | Out-Null
        Wait-Vault
        $restoreInit = Invoke-VaultApi -Method PUT -Path "/v1/sys/init" -Body @{ secret_shares = 5; secret_threshold = 3 }
        $restoreKeys = @($restoreInit.keys_base64 | Select-Object -First 3)
        foreach ($key in $restoreKeys) {
            Invoke-VaultApi -Method PUT -Path "/v1/sys/unseal" -Body @{ key = [string]$key } | Out-Null
        }
        Wait-VaultActive
        $restoreRoot = [string]$restoreInit.root_token
        docker cp $snapshot "${restoreContainer}:/tmp/sec01.snap" | Out-Null
        docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$restoreRoot $restoreContainer vault operator raft snapshot restore -force /tmp/sec01.snap | Out-Null
        Start-Sleep -Seconds 8
        foreach ($key in @($unsealKeys | Select-Object -First 3)) {
            try {
                Invoke-VaultApi -Method PUT -Path "/v1/sys/unseal" -Body @{ key = [string]$key } | Out-Null
            } catch { }
        }
        Wait-VaultActive
        $restored = Invoke-VaultApi -Method GET -Path "/v1/pdp/data/$Path" -Token $SourceToken
        if ($restored.data.data.value -ne $ExpectedValue) {
            throw "Valor restaurado nao corresponde ao snapshot Raft."
        }
        Write-Output "SEC-01 backup/restore rehearsal PASS em instancia descartavel isolada."
    } finally {
        & docker compose @restoreCompose down --volumes --remove-orphans 2>$null | Out-Null
        if (Test-Path $snapshot) { Remove-Item -LiteralPath $snapshot -Force }
        $script:vaultPort = $savedPort
        if ($null -eq $savedVolume) { Remove-Item Env:VAULT_VOLUME_NAME -ErrorAction SilentlyContinue } else { $env:VAULT_VOLUME_NAME = $savedVolume }
        if ($null -eq $savedNetwork) { Remove-Item Env:VAULT_NETWORK_NAME -ErrorAction SilentlyContinue } else { $env:VAULT_NETWORK_NAME = $savedNetwork }
        if ($null -eq $savedAddress) { Remove-Item Env:VAULT_ADDR -ErrorAction SilentlyContinue } else { $env:VAULT_ADDR = $savedAddress }
        $env:VAULT_API_HOST_PORT = $savedPort
    }
}

try {
    foreach ($volume in $normalVolumes) {
        $snapshot = Get-VolumeSnapshot $volume
        if ($null -eq $snapshot) { throw "Volume normal esperado nao existe: $volume" }
        $volumeSnapshots[$volume] = $snapshot
    }
    Set-Sec01Environment
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $vaultCompose = @("--project-name", $vaultProject, "--env-file", $envPath, "-f", $vaultComposeFile)
    $controlCompose = @("--project-name", $controlProject, "--env-file", $envPath, "-f", $controlComposeFile)

    Invoke-Compose $vaultCompose down --volumes --remove-orphans | Out-Null
    Invoke-Compose $controlCompose down --volumes --remove-orphans | Out-Null
    Invoke-Compose $vaultCompose up --detach vault | Out-Null
    Wait-Vault

    $init = Invoke-VaultApi -Method PUT -Path "/v1/sys/init" -Body @{ secret_shares = 5; secret_threshold = 3 }
    $unsealKeys = @($init.keys_base64 | Select-Object -First 3)
    foreach ($key in $unsealKeys) {
        Invoke-VaultApi -Method PUT -Path "/v1/sys/unseal" -Body @{ key = [string]$key } | Out-Null
    }
    Wait-VaultActive
    $rootToken = [string]$init.root_token

    $mounts = Invoke-VaultApi -Method GET -Path "/v1/sys/mounts" -Token $rootToken
    if (-not ($mounts.PSObject.Properties.Name -contains "pdp/")) {
        Invoke-VaultApi -Method POST -Path "/v1/sys/mounts/pdp" -Token $rootToken -Body @{ type = "kv"; options = @{ version = "2" } } | Out-Null
    }
    $auths = Invoke-VaultApi -Method GET -Path "/v1/sys/auth" -Token $rootToken
    if (-not ($auths.PSObject.Properties.Name -contains "approle/")) {
        Invoke-VaultApi -Method POST -Path "/v1/sys/auth/approle" -Token $rootToken -Body @{ type = "approle" } | Out-Null
    }

    $org1 = [guid]::NewGuid().ToString()
    $domain1 = [guid]::NewGuid().ToString()
    $connection1 = [guid]::NewGuid().ToString()
    $org2 = [guid]::NewGuid().ToString()
    $domain2 = [guid]::NewGuid().ToString()
    $connection2 = [guid]::NewGuid().ToString()
    $secretRef1 = "sref_" + ([guid]::NewGuid().ToString("N")).Substring(0, 20)
    $secretRef2 = "sref_" + ([guid]::NewGuid().ToString("N")).Substring(0, 20)
    $marker1 = "synthetic-sec01-value-" + $suffix
    $marker2 = "synthetic-sec01-rotated-" + $suffix
    $workloadId = "sec01-runtime-$suffix"

    Invoke-Compose $controlCompose up --detach control-db | Out-Null
    Wait-Database
    Invoke-Compose $controlCompose run --rm control-migrate | Out-Null
    Invoke-ControlSql @"
INSERT INTO organizations (id, slug, status) VALUES ('$org1', 'sec01-org-$suffix', 'active'), ('$org2', 'sec01-other-org-$suffix', 'active');
INSERT INTO domains (id, organization_id, slug) VALUES ('$domain1', '$org1', 'sec01-domain-$suffix'), ('$domain2', '$org2', 'sec01-other-domain-$suffix');
INSERT INTO connections (id, domain_id, name, connection_type, config, secret_ref)
VALUES ('$connection1', '$domain1', 'sec01-primary-$suffix', 's3', '{"endpoint":"http://synthetic.invalid","bucket":"sec01-test","region":"local","path_style":true,"use_ssl":false}', '$secretRef1'),
       ('$connection2', '$domain2', 'sec01-cross-domain-$suffix', 's3', '{"endpoint":"http://synthetic.invalid","bucket":"sec01-test-other","region":"local","path_style":true,"use_ssl":false}', '$secretRef2');
"@

    $safeConnection = $connection1.Replace('-', '')
    $safeWorkload = $workloadId -replace '[^A-Za-z0-9_-]', '-'
    $policyName = "pdp-connection-$safeConnection"
    $roleName = "pdp-workload-$safeWorkload-$safeConnection"
    $secretPath = "connections/$domain1/$connection1/$secretRef1"
    $policy = @"
path "pdp/data/$secretPath" {
  capabilities = ["read"]
}
"@
    Invoke-VaultApi -Method PUT -Path "/v1/sys/policies/acl/$policyName" -Token $rootToken -Body @{ policy = $policy } | Out-Null
    Invoke-VaultApi -Method POST -Path "/v1/auth/approle/role/$roleName" -Token $rootToken -Body @{
        token_policies = @($policyName)
        token_type = "service"
        token_ttl = "5m"
        token_max_ttl = "10m"
        secret_id_ttl = "10m"
        secret_id_num_uses = 1
        metadata = @{ domain_id = $domain1; connection_id = $connection1; workload_id = $workloadId }
    } | Out-Null
    $roleId = (Invoke-VaultApi -Method GET -Path "/v1/auth/approle/role/$roleName/role-id" -Token $rootToken).data.role_id
    Set-VaultSecret -Token $rootToken -Path $secretPath -SecretRef $secretRef1 -Value $marker1

    Write-WorkloadCredential -Token $rootToken -RoleName $roleName -RoleId $roleId -DomainId $domain1 -ConnectionId $connection1 -WorkloadId $workloadId
    Write-JsonFile $caseFile @{ mode = "available"; connection_id = $connection1; other_connection_id = $connection2; expected_value = $marker1 }

    Invoke-IntegrationTest "available"
    $sameSecretRef = (& docker compose @controlCompose exec -T control-db psql -U $dbUser -d $dbName -tA -c "SELECT secret_ref FROM connections WHERE id = '$connection1';").Trim()
    if ($LASTEXITCODE -ne 0 -or $sameSecretRef -ne $secretRef1) { throw "secret_ref da Connection mudou durante a rotacao inicial." }

    Copy-Item -LiteralPath $credentialFile -Destination $previousCredentialFile -Force
    $firstCredential = Get-Content -LiteralPath $credentialFile -Raw | ConvertFrom-Json
    Write-WorkloadCredential -Token $rootToken -RoleName $roleName -RoleId $roleId -DomainId $domain1 -ConnectionId $connection1 -WorkloadId $workloadId
    $secondCredential = Get-Content -LiteralPath $credentialFile -Raw | ConvertFrom-Json
    if ($firstCredential.role_id -ne $secondCredential.role_id -or
        $firstCredential.secret_id -eq $secondCredential.secret_id) {
        throw "As execucoes sucessivas nao receberam SecretIDs distintos para o mesmo workload."
    }
    Invoke-IntegrationTest -Mode "previous_credential" -CredentialPath $previousCredentialFile -TestFilter "previous_workload_credential"
    Write-Output "SEC-01 successive workload credentials PASS (SecretIDs distintos; credencial anterior negada)."
    Set-VaultSecret -Token $rootToken -Path $secretPath -SecretRef $secretRef1 -Value $marker2
    $case = Get-Content -LiteralPath $caseFile -Raw | ConvertFrom-Json
    $case.expected_value = $marker2
    Write-JsonFile $caseFile $case
    Invoke-IntegrationTest "available"
    $sameSecretRef = (& docker compose @controlCompose exec -T control-db psql -U $dbUser -d $dbName -tA -c "SELECT secret_ref FROM connections WHERE id = '$connection1';").Trim()
    if ($LASTEXITCODE -ne 0 -or $sameSecretRef -ne $secretRef1) { throw "rotacao alterou a Connection, mas deveria alterar somente o valor no Vault." }

    Invoke-BackupRestoreRehearsal -SourceToken $rootToken -Path $secretPath -ExpectedValue $marker2

    Write-WorkloadCredential -Token $rootToken -RoleName $roleName -RoleId $roleId -DomainId $domain1 -ConnectionId $connection1 -WorkloadId $workloadId

    Invoke-VaultApi -Method PUT -Path "/v1/sys/seal" -Token $rootToken | Out-Null
    Invoke-FailureTest "sealed"
    Invoke-Compose $vaultCompose stop vault | Out-Null
    Invoke-FailureTest "unavailable"
    Invoke-Compose $vaultCompose start vault | Out-Null
    Wait-Vault
    foreach ($key in $unsealKeys) {
        Invoke-VaultApi -Method PUT -Path "/v1/sys/unseal" -Body @{ key = [string]$key } | Out-Null
    }
    Wait-VaultActive
    Invoke-IntegrationTest "available"

    Write-Output "SEC-01 resource snapshot (docker stats --no-stream):"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $vaultContainer "$controlProject-control-db-1"

    Invoke-Compose $vaultCompose down --volumes --remove-orphans | Out-Null
    Invoke-Compose $controlCompose down --volumes --remove-orphans | Out-Null
    foreach ($volume in $normalVolumes) { Assert-VolumeSnapshot $volume $volumeSnapshots[$volume] }
    Write-Output "SEC-01 validado em ambiente descartavel; persistencia, escopo, rotacao, revogacao, sealed/unavailable e preservacao dos volumes passaram."
} finally {
    try {
        $vaultCompose = @("--project-name", $vaultProject, "--env-file", $envPath, "-f", $vaultComposeFile)
        $controlCompose = @("--project-name", $controlProject, "--env-file", $envPath, "-f", $controlComposeFile)
        & docker compose @vaultCompose down --volumes --remove-orphans 2>$null | Out-Null
        & docker compose @controlCompose down --volumes --remove-orphans 2>$null | Out-Null
    } finally {
        if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}
