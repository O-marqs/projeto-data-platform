# FND-02 - Validation Evidence

Status: `FND-02 = CONCLUIDO`

This evidence validates the version homologation and reproducibility scope for the local data platform laboratory.

## Environment

| Item | Value |
|---|---|
| Operating system | Windows 11 Pro, build 26200 |
| Docker Engine | 28.0.4 |
| Docker Compose | 2.34.0-desktop.1 |
| Docker architecture | linux/amd64 through Docker Desktop/WSL2 |
| Execution date | 2026-09-21 |
| Repository | `O-marqs/projeto-data-platform` |
| Baseline validated commit | `5c746ff` |
| Final review commit | `<filled after final review commit>` |
| Clean-install project | `pdp-fnd02-86d36067104d` |
| Persistent test project | `pdp-fnd01` |

## Homologated components

| Component | Version | Reproducibility reference |
|---|---|---|
| RustFS | 1.0.0-alpha.81 | Registry manifest `sha256:4ee605dfe7c6548d1fa1856357e8a1eccd929e3176acf933fafeba3ce09a69f9` |
| Polaris | 1.7.0 | Registry manifest `sha256:3495f67f38cca33892a045f7dd3f46eb52387f0fd52d4145538a772fd8aedad7` |
| Polaris admin tool | 1.7.0 | Registry manifest `sha256:3d8a24cea57aef3b71a0d7b09e5d2278d01e7e1b30071bf6648f2a6953322cca` |
| PostgreSQL | 18.6 | Registry manifest `sha256:86c951e05bf56c93d95d397747fb8820ac76cc3bedb78f43abd83eedbe3666ae` |
| Spark | 3.5.9-java17-python3 | Registry manifest `sha256:f3d6eaa8bab8ec2e38f3c3918a5b2f8b253c95bcb19f9e87ad0e0cdacf9df2d5` |
| AWS CLI | 2.36.44 | Registry manifest `sha256:e8467f2c319f9bc9a1471808a69949a76915e9c95eaf4a09ece9f9e85fd32747` |
| curl image | 8.22.0 | Registry manifest `sha256:a39f52cab21d7e283448a9f73032dfb578ffcea9edaaa90c1d637117149b337f` |
| Java runtime | 17.0.19 | Reported by `spark-submit` |
| Scala runtime | 2.12.18 | Reported by the Spark 3.5.9 runtime |
| Python runtime | 3.10.12 | Reported by `spark-submit` |
| PySpark | 3.5.9 | Reported by `spark-submit` |
| Iceberg Spark runtime | 1.10.1 | Maven SHA-256 `39ea09e6c03550a300b9d9ab498949836d2d434e441da4c12a943a086e396940` |
| Iceberg AWS bundle | 1.10.1 | Maven SHA-256 `86bf20892ea5b4c17688f19b075399885f6aa5303f6b2dc9f491e76ceef9633b` |

The image references in `infra/local/docker-compose.yml` use a fixed tag plus digest. The Maven coordinates and their SHA-256 values are recorded in `verify-iceberg-artifacts.py` and this matrix. No `latest` reference was found.

## Architecture validation

The effective path was validated as:

```text
PySpark / Spark SQL
  -> Iceberg Spark runtime
  -> Spark REST catalog
  -> Apache Polaris
  -> RustFS S3 API
```

Polaris state is persisted through its PostgreSQL configuration. The catalog bootstrap reports the Polaris catalog configured with `s3://data-platform` and the RustFS endpoint. Spark is configured with `SparkCatalog`, `type=rest`, and the Polaris REST URI; no local or in-memory catalog is configured as a fallback.

## Test results

| Test | Result | Evidence |
|---|---|---|
| `docker compose config` | PASS | Compose rendered successfully with fixed image digests |
| RustFS health | PASS | Container healthy |
| PostgreSQL health | PASS | Container healthy |
| Polaris health | PASS | Container healthy |
| Bucket created | PASS | `data-platform` bucket available through the S3-compatible API |
| Polaris catalog created | PASS | Catalog bootstrap completed against Polaris |
| Clean install | PASS | `scripts/fnd02-clean-validation.ps1`; isolated project and volumes |
| Iceberg namespace | PASS | Namespace `lab` |
| Iceberg table | PASS | `polaris.lab.fnd01_test` |
| Write 3 records | PASS | `FND01_WRITE=PASS` |
| Read 3 records | PASS | `FND01_READ=PASS rows=3` |
| Objects in RustFS | PASS | 3 `.parquet`, 2 `.metadata.json`, and 2 `.avro` objects |
| Stop without removing volumes | PASS | Compose stop/down path preserved named volumes |
| Restart | PASS | All services healthy after restart |
| Polaris persisted | PASS | Namespace and table resolved after restart without bootstrap recreation |
| Table persisted | PASS | `FND01_TABLE=PASS` in verify mode |
| Data persisted | PASS | `FND01_RESTART_READ=PASS table_and_data_persisted=true` |
| Verify does not recreate data | PASS | Verify mode only describes and reads the existing table; no create or append path |
| Repeated execution is idempotent | PASS | Second run reported `existing_rows=3`; object counts remained stable |
| Fixed versions | PASS | Version matrix and Compose references are pinned |
| No `latest` | PASS | Repository scan passed |
| Dependency checksums | PASS | Maven SHA-256 values recorded in the version matrix and this file |
| Secrets absent from Git | PASS | `.env` is not tracked; no real credential pattern found in tracked files |
| Secrets absent from evidence | PASS | No raw Compose output, token, password, access key, or secret key was versioned |
| ADR updated | PASS | ADR-020 records reproducibility and portability consequences |
| Version matrix updated | PASS | `docs/architecture/fnd02-version-matrix.md` |
| Airflow installed | NOT APPLICABLE | Explicitly outside FND-02 scope; only planning is documented |

## Persistence and idempotence procedure

The clean validation executed the complete sequence with an isolated Compose project:

1. Create a synthetic, untracked environment file and unique named volumes.
2. Render the Compose configuration and start the services.
3. Bootstrap the bucket and Polaris catalog.
4. Create the namespace and table, write three records, and read three records.
5. List RustFS objects directly.
6. Stop and start the environment without deleting volumes.
7. Run verify mode without recreating the namespace, table, or data.
8. Remove only the isolated validation resources.

The persistent project was then executed again over the same named volumes. It reported `existing_rows=3`, read exactly three records, and retained the same object counts. No table recreation was used for the restart verification.

## Measured consumption

The following Docker samples were captured with `docker stats --no-stream` while the persistent test project was healthy. CPU and memory are instantaneous samples, not resource limits.

| Service | CPU | Memory | Host memory |
|---|---:|---:|---:|
| RustFS | 0.71% | 107.6 MiB | 1.21% |
| Polaris | 4.67% | 325.6 MiB | 3.68% |
| PostgreSQL | 0.00% | 28.21 MiB | 0.32% |
| Spark verify sample | approximately 362% peak | approximately 804.8 MiB peak | sampled detached container |

| Timing | Value |
|---|---:|
| Cold start | 10.9 s |
| Smoke test | 50.7 s |
| Restart + verify | 80.4 s |
| Full measured run | 145 s |

The timing run used images already present locally. The isolated clean-install test also passed; image pulls and Maven Central downloads are environment-dependent and are not included in the timing values above.

## Security checks

- `.env` is ignored and is not tracked.
- `.env.example` contains placeholders and fixed-version metadata only.
- No real access key, secret key, PostgreSQL password, OAuth client secret, or token was found in tracked files.
- The bootstrap script contains only the authorization header construction required to send its in-memory token; it does not print or persist the token.
- No raw logs or rendered Compose environment were saved in the repository.

## Final review revalidation - 2026-09-22

This section preserves the original 2026-09-21 evidence above and records the
final PR review requested for PDP-20/FND-02.

### Files changed in the final review

- `.env.example`
- `infra/local/docker-compose.yml`
- `scripts/fnd01.ps1`
- `scripts/fnd02-clean-validation.ps1`
- `scripts/fnd02-checksum-validation.ps1`
- `experiments/fnd01/scripts/spark-entrypoint.sh`
- `experiments/fnd01/scripts/verify-iceberg-artifacts.py`
- `experiments/fnd01/README.md`
- `docs/architecture/fnd02-version-matrix.md`
- `docs/adr/ADR-020-fnd01-catalogo-local.md`
- this evidence file

### Port coexistence

The Compose file keeps the normal FND-01 host ports as defaults and exposes
simple `*_HOST_PORT` overrides. The clean-validation script sets the five
published host ports to `0`, allowing Docker to assign ephemeral ports while
leaving all container-to-container endpoints unchanged.

The coexistence test was executed with the persistent FND-01 project already
running and the isolated project `pdp-fnd02-f052f1ccdcb9` starting with unique
volumes and synthetic credentials. Result: `PASS`. The persistent FND-01
containers remained healthy and its volumes were not removed. The isolated
project completed write/read, restart/verify, and cleanup successfully.

### Maven checksum validation

`verify-iceberg-artifacts.py` downloads the two fixed Iceberg artifacts into a
temporary cache, validates the expected SHA-256 values from the environment,
and writes the verified paths for the Spark entrypoint. A cached file is hashed
again and a mismatch fails before the file is passed to Spark. The entrypoint
uses `--jars` only after this validation; the JARs are not versioned.

Positive and cache results:

```text
FND02_MAVEN_CHECKSUM=PASS artifact=iceberg-spark-runtime-3.5_2.12 source=download sha256=39ea09e6c03550a300b9d9ab498949836d2d434e441da4c12a943a086e396940
FND02_MAVEN_CHECKSUM=PASS artifact=iceberg-aws-bundle source=download sha256=86bf20892ea5b4c17688f19b075399885f6aa5303f6b2dc9f491e76ceef9633b
FND02_MAVEN_CHECKSUM=PASS artifact=iceberg-spark-runtime-3.5_2.12 source=cache sha256=39ea09e6c03550a300b9d9ab498949836d2d434e441da4c12a943a086e396940
FND02_MAVEN_CHECKSUM=PASS artifact=iceberg-aws-bundle source=cache sha256=86bf20892ea5b4c17688f19b075399885f6aa5303f6b2dc9f491e76ceef9633b
FND02_MAVEN_CACHE=PASS
```

Negative result with an all-zero expected checksum, executed in a temporary
container and without changing the homologated values:

```text
FND02_MAVEN_CHECKSUM=FAIL reason=checksum mismatch for downloaded iceberg-spark-runtime-3.5_2.12
FND02_MAVEN_NEGATIVE=PASS
```

### Regression results

| Test | Result | Evidence |
|---|---|---|
| Compose render after port and checksum changes | PASS | `docker compose config --quiet` |
| PowerShell script parse | PASS | `fnd01.ps1`, clean validation, checksum validation |
| Persistent FND-01 write/read | PASS | `FND01_WRITE=PASS existing_rows=3`, `FND01_READ=PASS rows=3` |
| RustFS objects | PASS | 3 Parquet, 2 metadata JSON, 2 Avro |
| Persistent restart and verify | PASS | `FND01_RESTART_READ=PASS table_and_data_persisted=true` |
| Verify without recreation | PASS | Existing table/data read without create or append |
| FND-01 idempotence | PASS | Existing row count remained 3 |
| FND-02 clean install with FND-01 coexistence | PASS | Isolated project completed with host ports set to 0 |
| Automatic Maven checksum positive test | PASS | Download and cache paths both verified |
| Automatic Maven checksum negative test | PASS | Deliberate mismatch returned exit code 1 |

The first post-change persistent attempt exposed a transient Polaris `401
NotAuthorized` during the bootstrap-to-Spark handoff. The runner now retries
Spark at most three times with a five-second delay and still fails the test if
all attempts fail. The final full regression completed without requiring a
retry marker and returned `FND01_RESTART=PASS`.

Final persistent regression timings:

| Timing | Value |
|---|---:|
| Cold start | 8.8 s |
| Smoke test | 41.4 s |
| Restart + verify | 65.8 s |
| Full run | 118.8 s |

Clean coexistence timings were approximately 30.1 s cold start, 52.5 s smoke,
67.2 s restart/verify, and 152.7 s overall. These values include the local
Docker and Maven network conditions at execution time.

## Limitations

- The Spark entrypoint resolves the two fixed Iceberg artifacts from Maven Central at runtime. Their coordinates and checksums are documented, but the JARs are not vendored in Git and a first execution requires network access.
- Validation was executed on Windows 11 with Docker Desktop/WSL2 and `linux/amd64`. Linux-native and ARM64 execution were not run.
- RustFS remains the pinned alpha release selected by the existing FND-01 laboratory; upgrading it would be a separate compatibility decision.
- Resource values are local samples on a developer machine, not production capacity limits or a FinOps baseline.
- Airflow and its providers were intentionally not installed or implemented in FND-02.
