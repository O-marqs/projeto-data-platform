param(
    [ValidateSet("up", "status", "init", "unseal", "configure", "down", "clean")]
    [string]$Action = "status",
    [string]$ProjectName = "pdp-vault",
    [string]$EnvFile = "",
    [string]$RecoveryFile = "",
    [string]$CredentialFile = "",
    [string]$DomainId = "",
    [string]$ConnectionId = "",
    [string]$WorkloadId = "",
    [string]$SecretRef = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeFile = Join-Path $repoRoot "infra\local\vault\docker-compose.yml"
$envPath = if ($EnvFile) { (Resolve-Path $EnvFile).Path } else { Join-Path $repoRoot ".env" }

if (-not (Test-Path $envPath)) {
    throw "Arquivo .env nao encontrado. Copie .env.example para .env e ajuste os valores locais."
}

$composeBase = @("--project-name", $ProjectName, "--env-file", $envPath, "-f", $composeFile)
$port = 18200
$portSetting = Get-Content $envPath | Where-Object { $_ -match '^\s*VAULT_API_HOST_PORT\s*=' } | Select-Object -First 1
if ($portSetting -and $portSetting -match '=\s*(\d+)\s*$') {
    $port = [int]$Matches[1]
}
$vaultAddress = "http://127.0.0.1:$port"
$kvMount = "pdp"
$kvSetting = Get-Content $envPath | Where-Object { $_ -match '^\s*VAULT_KV_MOUNT\s*=' } | Select-Object -First 1
if ($kvSetting -and $kvSetting -match '=\s*([^\s]+)\s*$') {
    $kvMount = $Matches[1]
}
$approleMount = "approle"
$approleSetting = Get-Content $envPath | Where-Object { $_ -match '^\s*VAULT_APPROLE_MOUNT\s*=' } | Select-Object -First 1
if ($approleSetting -and $approleSetting -match '=\s*([^\s]+)\s*$') {
    $approleMount = $Matches[1]
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker compose @composeBase @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose falhou com codigo $LASTEXITCODE."
    }
}

function Get-FullExternalPath {
    param([string]$Path, [string]$Description)
    if (-not $Path) {
        throw "$Description e obrigatorio e deve ficar fora do repositorio."
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootWithSeparator = $repoRoot.TrimEnd('\') + '\'
    if ($fullPath.Equals($repoRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description deve ficar fora do repositorio."
    }
    $parent = Split-Path -Parent $fullPath
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    return $fullPath
}

function Invoke-VaultApi {
    param(
        [ValidateSet("GET", "POST", "PUT")][string]$Method,
        [string]$Path,
        [string]$Token = "",
        [hashtable]$Body = $null
    )
    $headers = @{}
    if ($Token) {
        $headers["X-Vault-Token"] = $Token
    }
    $params = @{
        Method = $Method
        Uri = "$vaultAddress$Path"
        Headers = $headers
        ContentType = "application/json"
        ErrorAction = "Stop"
    }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        throw "Vault API falhou para $Method $Path; consulte o status do servico sem registrar tokens ou valores secretos."
    }
}

function Get-VaultStatus {
    return Invoke-VaultApi -Method GET -Path "/v1/sys/seal-status"
}

function Wait-VaultActive {
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "$vaultAddress/v1/sys/health" -TimeoutSec 3
            if ($response.StatusCode -eq 200) { return }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw "Vault nao ficou ativo depois do unseal."
}

function ConvertFrom-SecureStringValue {
    param([Security.SecureString]$Value)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Write-SecureJson {
    param([string]$Path, [object]$Value)
    $fullPath = Get-FullExternalPath -Path $Path -Description "Arquivo de credenciais"
    $json = $Value | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $fullPath -Value $json -Encoding UTF8 -NoNewline
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        & icacls $fullPath /inheritance:r /grant:r "${env:USERNAME}:(F)" | Out-Null
    }
    return $fullPath
}

switch ($Action) {
    "up" {
        Invoke-Compose up --detach vault
        Write-Output "Vault iniciado no endpoint local $vaultAddress."
    }
    "status" {
        $status = Get-VaultStatus
        Write-Output ("initialized={0} sealed={1} version={2}" -f $status.initialized, $status.sealed, $status.version)
    }
    "init" {
        $fullRecoveryFile = Get-FullExternalPath -Path $RecoveryFile -Description "Arquivo de recovery"
        $status = Get-VaultStatus
        if ($status.initialized) {
            throw "Vault ja foi inicializado; nao execute init novamente."
        }
        $result = Invoke-VaultApi -Method PUT -Path "/v1/sys/init" -Body @{
            secret_shares = 5
            secret_threshold = 3
        }
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fullRecoveryFile -Encoding UTF8 -NoNewline
        Write-Output "Vault inicializado. Material de recovery gravado fora do repositorio; mantenha-o offline."
    }
    "unseal" {
        $fullRecoveryFile = Get-FullExternalPath -Path $RecoveryFile -Description "Arquivo de recovery"
        $recovery = Get-Content -LiteralPath $fullRecoveryFile -Raw | ConvertFrom-Json
        $unsealKeys = if ($recovery.keys_base64) { $recovery.keys_base64 } else { $recovery.unseal_keys_b64 }
        if (-not $unsealKeys) {
            throw "Arquivo de recovery nao contem chaves de unseal."
        }
        # init fixes the threshold at three shares; the recovery file contains
        # only the generated key material, not a trusted execution setting.
        $threshold = 3
        $keys = @($unsealKeys | Select-Object -First $threshold)
        foreach ($key in $keys) {
            Invoke-VaultApi -Method PUT -Path "/v1/sys/unseal" -Body @{ key = [string]$key } | Out-Null
        }
        $status = Get-VaultStatus
        if ($status.sealed) {
            throw "Vault continua sealed; verifique o material de recovery fora do repositorio."
        }
        Wait-VaultActive
        Write-Output "Vault desbloqueado; nenhuma chave foi impressa."
    }
    "configure" {
        foreach ($value in @($DomainId, $ConnectionId, $WorkloadId, $SecretRef, $CredentialFile)) {
            if (-not $value) { throw "configure exige DomainId, ConnectionId, WorkloadId, SecretRef e CredentialFile." }
        }
        $parsedDomain = [guid]::Empty
        $parsedConnection = [guid]::Empty
        if (-not [guid]::TryParse($DomainId, [ref]$parsedDomain) -or
            -not [guid]::TryParse($ConnectionId, [ref]$parsedConnection) -or
            $SecretRef -notmatch '^sref_[A-Za-z0-9][A-Za-z0-9_-]{7,127}$') {
            throw "DomainId e ConnectionId devem ser UUIDs e SecretRef deve ser um identificador opaco sref_."
        }
        $status = Get-VaultStatus
        if (-not $status.initialized -or $status.sealed) {
            throw "Vault precisa estar inicializado e desbloqueado antes da configuracao."
        }
        $adminSecure = Read-Host "Token administrativo temporario do Vault" -AsSecureString
        $adminToken = ConvertFrom-SecureStringValue $adminSecure
        $secretSecure = Read-Host "Valor sintetico da Connection (nao sera exibido)" -AsSecureString
        $secretValue = ConvertFrom-SecureStringValue $secretSecure
        try {
            $mounts = Invoke-VaultApi -Method GET -Path "/v1/sys/mounts" -Token $adminToken
            if (-not ($mounts.PSObject.Properties.Name -contains "$kvMount/")) {
                Invoke-VaultApi -Method POST -Path "/v1/sys/mounts/$kvMount" -Token $adminToken -Body @{ type = "kv"; options = @{ version = "2" } } | Out-Null
            }
            $auths = Invoke-VaultApi -Method GET -Path "/v1/sys/auth" -Token $adminToken
            if (-not ($auths.PSObject.Properties.Name -contains "$approleMount/")) {
                Invoke-VaultApi -Method POST -Path "/v1/sys/auth/$approleMount" -Token $adminToken -Body @{ type = "approle" } | Out-Null
            }
            $safeConnection = $ConnectionId.Replace('-', '')
            $safeWorkload = ($WorkloadId -replace '[^A-Za-z0-9_-]', '-')
            $policyName = "pdp-connection-$safeConnection"
            $roleName = "pdp-workload-$safeWorkload-$safeConnection"
            $secretPath = "connections/$DomainId/$ConnectionId/$SecretRef"
            $policy = @"
path "$kvMount/data/$secretPath" {
  capabilities = ["read"]
}
"@
            Invoke-VaultApi -Method PUT -Path "/v1/sys/policies/acl/$policyName" -Token $adminToken -Body @{ policy = $policy } | Out-Null
            Invoke-VaultApi -Method POST -Path "/v1/auth/$approleMount/role/$roleName" -Token $adminToken -Body @{
                token_policies = @($policyName)
                token_type = "service"
                token_ttl = "5m"
                token_max_ttl = "10m"
                secret_id_ttl = "10m"
                secret_id_num_uses = 3
                metadata = @{
                    domain_id = $DomainId
                    connection_id = $ConnectionId
                    workload_id = $WorkloadId
                }
            } | Out-Null
            $roleId = (Invoke-VaultApi -Method GET -Path "/v1/auth/$approleMount/role/$roleName/role-id" -Token $adminToken).data.role_id
            $secretMetadata = @{
                domain_id = $DomainId
                connection_id = $ConnectionId
                workload_id = $WorkloadId
            } | ConvertTo-Json -Compress
            $secretId = (Invoke-VaultApi -Method POST -Path "/v1/auth/$approleMount/role/$roleName/secret-id" -Token $adminToken -Body @{ metadata = $secretMetadata }).data.secret_id
            Invoke-VaultApi -Method POST -Path "/v1/$kvMount/data/$secretPath" -Token $adminToken -Body @{ data = @{ secret_ref = $SecretRef; value = $secretValue } } | Out-Null
            $credentialPath = Write-SecureJson -Path $CredentialFile -Value @{ role_id = $roleId; secret_id = $secretId }
            Write-Output "Policy, AppRole e segredo configurados para uma Connection concreta. Credencial gravada em $credentialPath."
        } finally {
            if ($adminToken) { Clear-Variable adminToken -ErrorAction SilentlyContinue }
            if ($secretValue) { Clear-Variable secretValue -ErrorAction SilentlyContinue }
        }
    }
    "down" {
        Invoke-Compose down --remove-orphans
        Write-Output "Vault parado; volume persistente preservado."
    }
    "clean" {
        Invoke-Compose down --volumes --remove-orphans
        Write-Output "Somente os recursos do projeto Vault $ProjectName foram removidos."
    }
}
