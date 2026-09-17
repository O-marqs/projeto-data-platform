# Projeto Data Platform

Repositório local do projeto `PDP - Projeto Data Platform`, criado a partir do backlog Jira.

## Objetivo

Construir uma plataforma de dados reproduzível, segura e evolutiva, começando por uma fundação pequena e seguindo para um primeiro pipeline batch PostgreSQL -> Bronze/Silver/Gold com rastreabilidade, replay seguro e base para self-service.

## Escopo inicial

- Fundação de engenharia, ambiente local e CI.
- Primeiro pipeline batch reproduzível.
- Lakehouse com Apache Iceberg, catálogo técnico e object storage.
- Runtimes analíticos com PySpark, Spark SQL, Trino e dbt.
- Control Plane e portal para self-service governado.
- Observabilidade, recuperação, qualidade, contratos e governança computacional.

## Estrutura

```text
apps/
  control-plane-api/     API do plano de controle
  portal/                Portal e backoffice
pipelines/
  batch/                 Pipelines batch e jobs de ingestao/transformacao
libs/
  platform-contracts/    Contratos, specs e modelos compartilhados
infra/
  local/                 Ambiente local, containers e bootstrap
experiments/
  fnd01/                 Spike do laboratorio Spark + Iceberg + Polaris + RustFS
docs/
  adr/                   Decisoes arquiteturais
  jira/                  Rastreabilidade com Jira
tests/
  fixtures/              Fixtures e massa de validacao
```

## Jira

- Site: <https://marqs.atlassian.net>
- Projeto: `PDP`
- Nome: `Projeto Data Platform`
- Backlog inicial: [docs/jira/backlog.md](docs/jira/backlog.md)

## Primeiro laboratorio

O card `FND-01` fecha o primeiro laboratorio reproduzivel do caminho:

```text
PySpark -> Apache Iceberg -> Apache Polaris -> RustFS
                         \-> PostgreSQL (persistencia do catalogo)
```

O experimento nao implementa ainda Control Plane, portal, Airflow, Trino, dbt ou observabilidade distribuida. Consulte [experiments/fnd01/README.md](experiments/fnd01/README.md) para executar o smoke test e provar a persistencia apos restart.

## Primeiros passos planejados

1. Fechar a fundacao do MVP 00: ambiente local, CI, convencoes e ADRs minimas.
2. Criar fixture do primeiro pipeline.
3. Evoluir o laboratorio FND-01 para o primeiro pipeline batch.
4. Implementar o caminho PostgreSQL -> Bronze/Silver/Gold.
5. Registrar evidencias por issue Jira e commit.

## Status

FND-01 esta validado como spike local: a execucao completa do Docker gravou e leu a tabela Iceberg e repetiu a leitura apos restart sem remover os volumes persistentes.
