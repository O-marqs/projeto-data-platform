param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envExample = Join-Path $repoRoot ".env.example"
$verifier = (Resolve-Path (Join-Path $repoRoot "experiments\fnd01\scripts\verify-iceberg-artifacts.py")).Path

function Read-ExampleValue {
    param([string]$Name)
    $line = Get-Content $envExample | Where-Object { $_ -match "^$Name=" } | Select-Object -First 1
    if (-not $line) {
        throw "Valor $Name nao encontrado em .env.example."
    }
    return $line.Substring($Name.Length + 1)
}

$version = Read-ExampleValue "SPARK_VERSION"
$imageDigest = Read-ExampleValue "SPARK_IMAGE_DIGEST"
$icebergVersion = Read-ExampleValue "ICEBERG_VERSION"
$runtimeChecksum = Read-ExampleValue "ICEBERG_SPARK_RUNTIME_SHA256"
$bundleChecksum = Read-ExampleValue "ICEBERG_AWS_BUNDLE_SHA256"
$image = "apache/spark:$version@$imageDigest"
$mount = "${verifier}:/opt/fnd01/verify-iceberg-artifacts.py:ro"
$runtimeOverride = "iceberg-spark-runtime-3.5_2.12=$([string]::new('0', 64))"
$cacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "pdp-fnd02-checksum-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
$cacheMount = "${cacheDir}:/tmp/fnd02-checksum-cache"

try {
    $positiveBase = @(
        "run", "--rm", "--entrypoint", "/bin/sh",
        "-e", "ICEBERG_VERSION=$icebergVersion",
        "-e", "ICEBERG_SPARK_RUNTIME_SHA256=$runtimeChecksum",
        "-e", "ICEBERG_AWS_BUNDLE_SHA256=$bundleChecksum",
        "-v", $mount,
        "-v", $cacheMount,
        $image
    )
    $downloadArgs = $positiveBase + @("-c", "python3 /opt/fnd01/verify-iceberg-artifacts.py --cache-dir /tmp/fnd02-checksum-cache")
    $downloadOutput = @(& docker @downloadArgs 2>&1)
    $downloadExitCode = $LASTEXITCODE
    $downloadOutput | ForEach-Object { Write-Output $_ }
    if ($downloadExitCode -ne 0 -or -not ($downloadOutput -match "source=download")) {
        throw "Validacao positiva por download falhou."
    }

    $cacheArgs = $positiveBase + @("-c", "python3 /opt/fnd01/verify-iceberg-artifacts.py --cache-dir /tmp/fnd02-checksum-cache")
    $cacheOutput = @(& docker @cacheArgs 2>&1)
    $cacheExitCode = $LASTEXITCODE
    $cacheOutput | ForEach-Object { Write-Output $_ }
    if ($cacheExitCode -ne 0 -or -not ($cacheOutput -match "source=cache")) {
        throw "Validacao positiva de cache falhou."
    }
    Write-Output "FND02_MAVEN_CACHE=PASS"

    $negativeArgs = @(
        "run", "--rm", "--entrypoint", "/bin/sh",
        "-e", "ICEBERG_VERSION=$icebergVersion",
        "-e", "ICEBERG_SPARK_RUNTIME_SHA256=$runtimeChecksum",
        "-e", "ICEBERG_AWS_BUNDLE_SHA256=$bundleChecksum",
        "-v", $mount,
        $image,
        "-c",
        "set -e; python3 /opt/fnd01/verify-iceberg-artifacts.py --cache-dir /tmp/fnd02-checksum-negative --expected-sha256 '$runtimeOverride'"
    )
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $negativeOutput = @(& docker @negativeArgs 2>&1)
    $negativeExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $negativeOutput | ForEach-Object { Write-Output $_ }
    if ($negativeExitCode -eq 0 -or -not ($negativeOutput -match "FND02_MAVEN_CHECKSUM=FAIL")) {
        throw "Teste negativo nao falhou de forma controlada."
    }
    Write-Output "FND02_MAVEN_NEGATIVE=PASS"
}
finally {
    if (Test-Path $cacheDir) {
        Remove-Item -LiteralPath $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
