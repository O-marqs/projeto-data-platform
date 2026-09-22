# Projeto Data Platform

Monorepo do projeto `PDP - Projeto Data Platform`, rastreado no Jira.

## Objetivo

Construir uma plataforma de dados reproduzivel, segura e evolutiva. A fundacao atual prioriza um laboratorio local verificavel e convencoes que permitam evoluir o primeiro pipeline batch sem criar fronteiras artificiais.

## Estado atual

| Area | Estado | Evidencia ou referencia |
| --- | --- | --- |
| FND-01 | IMPLEMENTADO | [evidencia FND-01](experiments/fnd01/evidence/fnd01-validation-2026-09-17.md) |
| FND-02 | IMPLEMENTADO | [matriz de versoes](docs/architecture/fnd02-version-matrix.md) e [evidencia FND-02](experiments/fnd02/evidence/fnd02-validation-2026-09-21.md) |
| FND-03 | IMPLEMENTADO neste card | [organizacao do monorepo](docs/architecture/monorepo-organization.md) |
| Control Plane API | ESTRUTURA RESERVADA PARA EVOLUCAO | [apps/control-plane-api/README.md](apps/control-plane-api/README.md) |
| Portal | ESTRUTURA RESERVADA PARA EVOLUCAO | [apps/portal/README.md](apps/portal/README.md) |
| Contratos compartilhados | ESTRUTURA RESERVADA PARA EVOLUCAO | [libs/platform-contracts/README.md](libs/platform-contracts/README.md) |
| Pipeline batch | ESTRUTURA RESERVADA PARA EVOLUCAO | [pipelines/batch/README.md](pipelines/batch/README.md) |
| CI/CD, Airflow, Trino, dbt e Kubernetes | PLANEJADO | Nao implementado neste escopo |

Uma area com README de responsabilidade reservada nao e uma capability implementada. O unico runtime funcional atual e o laboratorio FND-01/FND-02.

## Estrutura

```text
apps/
  control-plane-api/     Area reservada para API do plano de controle
  portal/                Area reservada para portal e backoffice
pipelines/
  batch/                 Area reservada para pipelines batch
libs/
  platform-contracts/    Area reservada para contratos e specs compartilhados
infra/
  local/                 Ambiente local implementado para FND-01
experiments/
  fnd01/                 Laboratorio Spark + Iceberg + Polaris + RustFS
  fnd02/                 Evidencias de homologacao e instalacao limpa
docs/
  adr/                   Decisoes arquiteturais
  architecture/         Matrizes e regras da arquitetura
  jira/                  Rastreabilidade com Jira
tests/
  fixtures/              Area reservada para fixtures
scripts/                  Comandos operacionais dos laboratorios
```

As responsabilidades detalhadas, estados e regras de dependencias estao em [docs/architecture/monorepo-organization.md](docs/architecture/monorepo-organization.md).

## Jira e documentacao

- Site Jira: <https://marqs.atlassian.net>
- Projeto: `PDP - Projeto Data Platform`
- Backlog: [docs/jira/backlog.md](docs/jira/backlog.md)
- Referencias internas: Confluence `DP16` e `DP19`, conforme o card Jira

## Primeiro laboratorio

O FND-01 valida o fluxo:

```text
PySpark -> Apache Iceberg -> Iceberg REST Catalog -> Apache Polaris -> RustFS
                                      |
                                      +-> PostgreSQL persiste o estado do Polaris
```

Consulte [experiments/fnd01/README.md](experiments/fnd01/README.md) para o smoke test e [docs/architecture/fnd02-version-matrix.md](docs/architecture/fnd02-version-matrix.md) para a homologacao de versoes do FND-02.

## Pre-requisitos

- Git.
- Docker Desktop com Docker Compose v2.
- PowerShell 7 ou Windows PowerShell compativel com os scripts.
- Make e opcional; os scripts PowerShell sao a referencia.
- Acesso a internet na primeira obtencao das imagens e dependencias.

## Comandos locais

```powershell
Copy-Item .env.example .env
./scripts/fnd01.ps1 up
./scripts/fnd01.ps1 test
./scripts/fnd01.ps1 down
```

Para o FND-02, use os scripts de validacao de checksum e de instalacao limpa:

```powershell
./scripts/fnd02-checksum-validation.ps1
./scripts/fnd02-clean-validation.ps1
```

`down` preserva os volumes do laboratorio. `clean` remove containers, volumes e dados temporarios do FND-01; use-o somente quando a instalacao limpa for o objetivo. O FND-02 usa portas efemeras para coexistir com um ambiente FND-01 ativo.

## Contribuicao

Leia [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir uma mudanca. O arquivo define branch, commit, PR, evidencias, segredos, ADRs e limites de dependencias. A responsabilidade de revisao padrao esta em [.github/CODEOWNERS](.github/CODEOWNERS); isso nao transforma o revisor em Data Owner, Technical Owner ou dono de Data Product.

## Proximos passos

O proximo trabalho deve iniciar pelo FND-04 somente apos a revisao deste PR. FND-03 nao cria API, portal, pipeline, CI, banco, migracao, Airflow, Kubernetes ou um segundo repositorio.
