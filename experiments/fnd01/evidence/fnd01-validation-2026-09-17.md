# FND-01 - Evidencia de validacao - 2026-09-17

## Resultado

**FND-01 = CONCLUIDO**

Execucao realizada de verdade no commit `e383d8a` (`Harden FND-01 validation and portability`). A evidencia foi registrada neste arquivo no commit seguinte, sem alterar o codigo validado.

## Ambiente

- Sistema operacional: Microsoft Windows 11 Pro, build 26200.
- Runtime de containers: Docker Desktop, engine `28.0.4`.
- Docker Compose: `v2.34.0-desktop.1`.
- Data da execucao: 2026-09-17, America/Sao_Paulo.
- Volumes usados: `pdp_fnd01_postgres_data` e `pdp_fnd01_rustfs_data`.

## Componentes

| Componente | Versao validada |
| --- | --- |
| RustFS | `1.0.0-alpha.81` |
| Apache Polaris | `1.7.0` |
| Polaris Admin Tool | `1.7.0` |
| PostgreSQL | `18.6` |
| Apache Spark | `3.5.9-java17-python3` |
| Apache Iceberg runtime | `1.10.1`, Spark 3.5 / Scala 2.12 |
| Iceberg AWS bundle | `1.10.1` |

## Arquitetura comprovada

- `spark-entrypoint.sh` configura `SparkCatalog` com `type=rest`, extensao Iceberg e URI `http://polaris:8181/api/catalog`.
- O endpoint de gerenciamento do Polaris retornou o catalogo `fnd01_catalog` como `INTERNAL`, com `storageType=S3`, `default-base-location=s3://data-platform`, `endpoint=http://rustfs:9000`, `endpointInternal=http://rustfs:9000`, `pathStyleAccess=true` e `stsUnavailable=true`.
- O PostgreSQL respondeu com as tabelas do schema `polaris_schema`, incluindo `entities`, `events`, `grant_records` e `principal_authentication_data`.
- A listagem S3 direta no RustFS encontrou os objetos da tabela `lab/fnd01_test`.
- Nao ha catalogo local ou in-memory configurado; o catalogo usado pelo Spark e o REST catalog `polaris`.

## Testes

| Teste | Resultado | Evidencia observada |
| --- | --- | --- |
| `docker compose config` | PASS | Configuracao aceita sem erro. |
| RustFS health | PASS | Container `healthy`. |
| PostgreSQL health | PASS | Container `healthy`. |
| Polaris health | PASS | Container `healthy`. |
| Bucket criado | PASS | Bucket `data-platform` criado no laboratorio limpo. |
| Catalogo Polaris criado | PASS | `fnd01_catalog` retornado pelo endpoint de management. |
| Namespace Iceberg | PASS | `FND01_NAMESPACE=PASS name=lab`. |
| Tabela Iceberg | PASS | `FND01_TABLE=PASS name=polaris.lab.fnd01_test`. |
| Escrita de 3 registros | PASS | `FND01_WRITE=PASS rows=3` em ambiente limpo. |
| Leitura de 3 registros | PASS | `FND01_READ=PASS rows=3`. |
| Objetos no RustFS | PASS | 3 arquivos `.parquet`, 2 `.metadata.json` e 2 `.avro`. |
| Parar sem remover volumes | PASS | `docker compose stop` executado antes do restart. |
| Restart do ambiente | PASS | Containers subiram novamente com os mesmos volumes. |
| Polaris persistiu | PASS | Catalogo continuou disponivel e PostgreSQL manteve `polaris_schema`. |
| Tabela persistiu | PASS | `verify` listou explicitamente `lab.fnd01_test`, sem CREATE. |
| Dados persistiram | PASS | `verify` comparou os 3 registros completos, incluindo timestamps. |
| Idempotencia | PASS | Repeticoes de `test` e `down`/`up` nao duplicaram dados nem falharam por bucket, catalogo, namespace ou tabela existentes. |
| Segredos fora do Git | PASS | `.env` nao e rastreado; valores reais de secrets encontrados no Git: 0. |
| Segredos no compose/logs | PASS | Scan do `docker compose config` passou; apenas marcadores `FND01_*` foram considerados evidencia. |
| Imagens sem `latest` | PASS | Nenhuma tag de imagem `latest` encontrada. |

## Objetos encontrados no RustFS

```text
lab/fnd01_test/data/*.parquet                         3 objetos
lab/fnd01_test/metadata/*.metadata.json              2 objetos
lab/fnd01_test/metadata/*.avro                       2 objetos
```

Os nomes completos e tamanhos foram conferidos por `aws s3 ls --recursive` executado dentro do servico `rustfs-bucket-init`; nenhum segredo foi incluido nesta evidencia.

## Consumo medido

Os valores abaixo sao amostras de `docker stats --no-stream`, portanto sao aproximados para CPU e representam o uso observado no instante da coleta.

| Componente | CPU observado | Memoria observada |
| --- | ---: | ---: |
| RustFS | 0.13% | 107.5 MiB |
| Polaris | 0.21% | 307.3 MiB |
| PostgreSQL | 0.02% | 29.1 MiB |
| Spark durante smoke test | pico amostrado de 179.42% | pico amostrado de 810.9 MiB |

Tempos medidos no host, com imagens ja disponiveis localmente:

| Etapa | Tempo |
| --- | ---: |
| Cold start apos `clean` | 26.6 s |
| Smoke test `write-read` | 45.3 s |
| `docker compose stop` | 2.7 s |
| Restart + `verify` | 64.2 s |
| Repeticao completa de `scripts/fnd01.ps1 test` | 123.6 s |

O tempo do smoke inclui a resolucao/download dos artefatos Maven do Iceberg em um container Spark sob demanda.

## Logs e seguranca

- Nenhum log bruto foi versionado; somente marcadores e contagens redigidos foram registrados.
- Credenciais permanecem no `.env` local ignorado.
- Nao foram encontrados access keys, secret keys, senha PostgreSQL, client secret Polaris, tokens OAuth ou Authorization headers nos arquivos rastreados.

## Limitacoes reais

- Laboratorio local, com credenciais estaticas de desenvolvimento e `stsUnavailable=true`; STS/credential vending nao faz parte do FND-01.
- RustFS esta em release alpha e o armazenamento e um volume local unico, sem HA, TLS ou backup.
- A primeira execucao depende de Docker Hub e Maven Central.
- O fluxo depende de Docker Compose v2 e da rede interna entre os servicos; `localhost` e reservado ao acesso pelo host.
- O Spark e executado sob demanda como driver local; nao existe cluster, scheduler ou pipeline de producao.
