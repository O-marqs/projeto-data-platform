# FND-01 - Laboratorio Spark, Iceberg, Polaris e RustFS

## Objetivo

Validar o caminho minimo de ponta a ponta:

```text
PySpark / Spark SQL
        |
        v
Apache Iceberg REST Catalog
        |
        v
Apache Polaris 1.7.0
        |
        v
RustFS 1.0.0-alpha.81
        |
        v
Volume Docker persistente
```

O aceite principal e provar que namespace, tabela Iceberg e dados continuam disponiveis depois de parar os containers sem remover os volumes e inicia-los novamente.

## Arquitetura do laboratorio

- RustFS expoe S3 em `localhost:9000` e console em `localhost:9001`.
- Os servicos usam `http://rustfs:9000` na rede Docker; `localhost:9000` fica reservado ao acesso pelo host.
- PostgreSQL persiste o metastore JDBC do Polaris em um volume nomeado.
- Polaris expoe o catalogo REST em `localhost:8181` e health/metricas em `localhost:8182`.
- `polaris-catalog-init` cria `fnd01_catalog` de forma idempotente, apontando para o bucket `data-platform`.
- Spark roda sob demanda em container e usa `iceberg-spark-runtime-3.5_2.12` mais `iceberg-aws-bundle`.
- O experimento cria `polaris.lab.fnd01_test` e grava tres registros.

Versoes e referencias estao em [docs/architecture/fnd01-version-matrix.md](../../docs/architecture/fnd01-version-matrix.md). A matriz de homologacao com digests, checksums Maven e limites de portabilidade esta em [docs/architecture/fnd02-version-matrix.md](../../docs/architecture/fnd02-version-matrix.md).

A evidencia versionada da ultima validacao esta em [evidence/fnd01-validation-2026-09-17.md](evidence/fnd01-validation-2026-09-17.md).

## Pre-requisitos

- Docker Desktop em execucao.
- Docker Compose v2.
- PowerShell 5+ ou PowerShell 7+.
- Internet disponivel para baixar as imagens e dependencias Maven do Iceberg na primeira execucao.

O Compose usa digests Docker fixados por default. Os nomes de volume do FND-01
continuam sendo `pdp_fnd01_postgres_data` e `pdp_fnd01_rustfs_data`; uma
execucao limpa e isolada deve usar o script FND-02 descrito abaixo.
As portas publicadas no host mantem esses defaults para o FND-01 e podem ser
substituidas pelas variaveis `*_HOST_PORT`.

## Como executar

Na raiz do repositorio:

```powershell
Copy-Item .env.example .env
.\scripts\fnd01.ps1 up
```

O arquivo `.env` e ignorado pelo Git. Ajuste as credenciais locais se necessario.

Para executar o teste completo, incluindo escrita, leitura, parada sem remover volumes, subida e leitura novamente:

```powershell
.\scripts\fnd01.ps1 test
```

Com Make instalado, os atalhos equivalentes sao:

```text
make up
make test-fnd01
make down
make clean-fnd01
```

## Como verificar

O teste imprime marcadores sem credenciais:

```text
FND01_WRITE=PASS
FND01_NAMESPACE=PASS
FND01_TABLE=PASS
FND01_READ=PASS
FND01_RESTART_READ=PASS
FND01_RESTART=PASS
```

Tambem lista os objetos Iceberg no bucket RustFS para provar que houve escrita no storage.

O console RustFS fica em <http://localhost:9001> e o health do Polaris em <http://localhost:8182/q/health>.

## Restart e persistencia

O fluxo do script `test` e:

1. Sobe RustFS, PostgreSQL, Polaris e o bootstrap do catalogo.
2. Executa Spark em modo `write-read`.
3. Confirma objetos no bucket.
4. Executa `docker compose stop`, que para os containers sem remover os volumes.
5. Sobe novamente os servicos persistentes.
6. Executa Spark em modo `verify`, sem recriar a tabela ou os dados.
7. Confirma a mesma tabela e as mesmas tres linhas.

Para remover somente os containers e preservar os dados:

```powershell
.\scripts\fnd01.ps1 down
```

Para destruir tambem o PostgreSQL e o RustFS persistentes:

```powershell
.\scripts\fnd01.ps1 clean
```

`clean` remove os volumes nomeados `pdp_fnd01_postgres_data` e `pdp_fnd01_rustfs_data`; depois disso o laboratorio volta a ser uma instalacao limpa.

## Instalacao limpa do FND-02

Para repetir o laboratorio usando um projeto Compose, credenciais sinteticas e
volumes novos, sem depender dos recursos do FND-01:

```powershell
.\scripts\fnd02-clean-validation.ps1
```

O script remove somente os recursos do projeto temporario ao terminar. Ele nao
remove os volumes padrao do FND-01. Use `-KeepVolumes` apenas para inspecionar
os objetos antes da limpeza.

Durante a validacao limpa, as portas do host sao definidas como `0`, portanto o
Docker escolhe portas efemeras. A comunicacao do Spark, Polaris, PostgreSQL e
RustFS continua usando os endpoints internos da rede Compose. Assim, o FND-01
pode permanecer em execucao enquanto o FND-02 e validado, sem compartilhar
volumes ou disputar as portas `9000`, `9001`, `8181`, `8182` e `5432`.

Para validar os JARs Iceberg antes do Spark usa-los, execute:

```powershell
.\scripts\fnd02-checksum-validation.ps1
```

O primeiro ciclo baixa os dois artefatos e o segundo exercita o cache ja
verificado. O mesmo script executa um caso negativo com checksum incorreto e
exige falha controlada. A execucao normal usa os JARs locais somente depois da
validacao e passa seus caminhos ao `spark-submit`.

## Limites e dividas tecnicas

- As credenciais sao estaticas e exclusivas para desenvolvimento local.
- O laboratorio usa `stsUnavailable=true`; o Spark usa credenciais S3 locais injetadas pelo `.env`, e credential vending/STS ficam para uma etapa posterior.
- O Spark executa em um container sob demanda; nao ha cluster, scheduler ou pipeline de producao.
- O armazenamento e um volume local unico, sem alta disponibilidade, TLS ou backup.
- A imagem RustFS escolhida e uma release alpha fixada; isso deve ser revisitado antes de qualquer uso compartilhado.
- O laboratorio pressupoe Docker Compose v2 com rede entre servicos; endpoints publicados em `localhost` sao destinados ao host, nao a comunicacao entre containers.
