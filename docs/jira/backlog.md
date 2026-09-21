# Backlog Jira

Fonte: Jira `PDP - Projeto Data Platform` em <https://marqs.atlassian.net>.

## Epicos identificados

| Issue | Nome | Foco |
| --- | --- | --- |
| PDP-1 | MVP 00 - Fundacao de produto e engenharia | Ambiente, CI, interfaces e decisoes minimas |
| PDP-2 | MVP 01 - Primeiro pipeline batch reproduzivel | PostgreSQL -> Bronze/Silver/Gold Iceberg |
| PDP-3 | MVP 02 - Control Plane e self-service | API, portal, onboarding de dominio e regras compartilhadas |
| PDP-4 | MVP 03 - Multi-engine SQL | Spark SQL e Trino sobre catalogo coerente |
| PDP-5 | MVP 04 - Catalogo tecnico Iceberg com Polaris | Catalogo persistente, credenciais e acesso |
| PDP-6 | MVP 05 - Metadata, lineage e ownership | Ativos, responsaveis, linhagem e projecoes |
| PDP-7 | MVP 06 - Qualidade e publicacao controlada | Gates de qualidade, quarentena e recuperacao |
| PDP-8 | MVP 07 - Contratos e governanca computacional | Compatibilidade, politicas e auditoria |

## Decisoes iniciais do repo

- Comecar como monorepo para manter API, portal, pipelines, contratos e infra local rastreaveis juntos.
- Tratar o MVP 00 como fundacao, nao como entrega implementada.
- Separar artefatos executaveis de documentacao e evidencias.
- Registrar ADRs antes de escolhas com impacto em runtime, catalogo, storage ou contrato.

## FND-01 - Spike local validado

- Status: PASS no laboratorio local ponta a ponta.
- Fluxo validado: PySpark/Spark SQL -> Iceberg REST Catalog -> Apache Polaris -> RustFS, com PostgreSQL persistindo o estado do Polaris.
- Experimento: [`experiments/fnd01/`](../../experiments/fnd01/README.md)
- Infraestrutura: [`infra/local/docker-compose.yml`](../../infra/local/docker-compose.yml)
- Matriz de versoes: [`docs/architecture/fnd01-version-matrix.md`](../architecture/fnd01-version-matrix.md)
- ADR: [`docs/adr/ADR-020-fnd01-catalogo-local.md`](../adr/ADR-020-fnd01-catalogo-local.md)
- Evidencia: [fnd01-validation-2026-09-17.md](../../experiments/fnd01/evidence/fnd01-validation-2026-09-17.md) registra escrita, leitura, listagem de objetos no RustFS, persistencia apos reinicio, seguranca e consumo medido.

## Links documentais citados no Jira

- DP 01 - Visao do produto, escopo e metricas
- DP 03 - Data Mesh, personas, ownership e RACI
- DP 04 - Arquitetura, fronteiras e fluxos
- DP 06 - Self-service declarativo e Resource Specifications
- DP 07 - Contratos de API e comportamento de erros
- DP 08 - Lifecycle, Airflow, idempotencia e recuperacao
- DP 09 - Lakehouse, Iceberg, Polaris e object storage
- DP 10 - Runtimes, PySpark, Spark SQL, Trino e dbt
- DP 14 - Seguranca, identidade, segredos e auditoria
- DP 16 - Repositorios, engenharia, CI/CD e testes
- DP 17 - Observabilidade, operacao, incidentes e recuperacao
- DP 18 - Portal, backoffice e jornadas de self-service
- DP 19 - Registro de decisoes arquiteturais
- DP 20 - Compatibilidade, riscos, lacunas e fontes
