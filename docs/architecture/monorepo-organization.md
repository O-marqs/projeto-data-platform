# Organizacao do monorepo

## Objetivo e estados

Este documento fecha o FND-03/PDP-21. Ele define limites de responsabilidade para o monorepo sem criar servicos ou repositorios artificiais.

- `IMPLEMENTADO`: ha codigo executavel ou ambiente validado e evidencia correspondente.
- `ESTRUTURA RESERVADA PARA EVOLUCAO`: a area existe para orientar a evolucao, mas nao implementa a capability descrita.
- `PLANEJADO`: item de backlog ainda nao implementado.

Um README de uma area reservada e documentacao de intencao, nao uma implementacao.

## Mapa de responsabilidades

| Caminho | Responsabilidade | Estado |
| --- | --- | --- |
| `apps/control-plane-api/` | futura composicao HTTP/API do control plane | ESTRUTURA RESERVADA PARA EVOLUCAO |
| `apps/portal/` | futura interface de portal e backoffice | ESTRUTURA RESERVADA PARA EVOLUCAO |
| `libs/platform-contracts/` | futuros contratos, schemas e modelos compartilhados | ESTRUTURA RESERVADA PARA EVOLUCAO |
| `pipelines/batch/` | futuros jobs batch e transformacoes | ESTRUTURA RESERVADA PARA EVOLUCAO |
| `infra/local/` | Compose, configuracao e bootstrap do laboratorio local | IMPLEMENTADO para FND-01 |
| `experiments/fnd01/` | spike executavel Spark, Iceberg, Polaris e RustFS | IMPLEMENTADO |
| `experiments/fnd02/` | evidencias de checksum e instalacao limpa | IMPLEMENTADO |
| `experiments/fnd03/evidence/` | evidencias versionadas de organizacao e convencoes | IMPLEMENTADO neste card |
| `docs/adr/` | decisoes arquiteturais | IMPLEMENTADO |
| `docs/architecture/` | matrizes e regras de arquitetura | IMPLEMENTADO |
| `docs/jira/` | rastreabilidade do backlog | IMPLEMENTADO |
| `tests/fixtures/` | futura massa reutilizavel de validacao | ESTRUTURA RESERVADA PARA EVOLUCAO |
| CI/CD, Airflow, Trino, dbt, Kubernetes e Terraform | automacao e capacidades futuras | PLANEJADO |

## Arvore atual

```text
apps/
  control-plane-api/README.md
  portal/README.md
libs/
  platform-contracts/README.md
pipelines/
  batch/README.md
infra/local/
experiments/fnd01/
experiments/fnd02/evidence/
experiments/fnd03/evidence/
docs/adr/
docs/architecture/
docs/jira/
tests/fixtures/README.md
```

## Limites de dependencia

Quando o primeiro codigo de dominio existir, a direcao esperada sera:

```text
dominio neutro -> casos de uso -> portas internas
adaptadores/runtime/infra -> portas internas e contratos
apps -> composicao de casos de uso e adaptadores
experiments -> validacao de runtime e infraestrutura
```

Regras:

- Dominio e casos de uso nao importam Spark, Airflow, FastAPI, Kubernetes ou SDK de provedor.
- Adaptadores conhecem detalhes de storage, catalogo, mensageria ou HTTP e traduzem para portas internas.
- Aplicacoes fazem composicao; nao devem duplicar regra de dominio.
- Experimentos podem depender de runtime e infraestrutura para provar uma hipotese, mas componentes de producao nao dependem de experimentos.
- Fixtures e evidencias nao sao dependencias de runtime.
- Contratos estaveis devem ser versionados e mudancas quebrantes devem ser documentadas.

Nao existe hoje `core`, dominio, casos de uso ou portas internas implementados. Portanto, nao ha um teste de isolamento de core a executar e nao foi criado um pacote vazio para simular essa fronteira.

## Auditoria do estado atual

A auditoria do commit base encontrou executaveis somente em scripts PowerShell/shell e nos experimentos FND-01. `run_fnd01.py` usa a biblioteca PySpark dentro do experimento; `verify-iceberg-artifacts.py` usa apenas biblioteca padrao. Nao ha imports de dominio, aplicacoes ou pipelines produtivos para avaliar, e nenhuma dependencia cruzada indevida foi introduzida por este card.

## Localizacao futura

- Dominio, casos de uso e portas internas: criar uma biblioteca real, como `libs/platform-core/`, somente quando houver codigo e ownership suficientes.
- Contratos: evoluir `libs/platform-contracts/` com schemas, specs e compatibilidade.
- API: implementar em `apps/control-plane-api/` quando houver casos de uso e contrato HTTP.
- Portal: implementar em `apps/portal/` quando existir fluxo de usuario definido.
- Pipelines: criar subpastas em `pipelines/batch/` com runtime, fixture e rerun documentados.
- Runtime especifico de spike: permanecer em `experiments/<id>/`; runtime de pipeline deve viver com o pipeline quando houver pipeline real.
- Adaptadores de infraestrutura: permanecer em `infra/` ou junto do componente dono quando houver necessidade concreta; nao criar `infra/adapters/` vazio.
- Testes, fixtures e evidencias: usar `tests/` e a pasta de evidencia do experimento sem transformar evidencia em codigo de producao.

## Criterios para extracao de repositorio

O monorepo so deve ser dividido quando houver beneficio concreto e varios criterios forem atendidos: ownership independente, ciclo de release ou deploy independente, isolamento de dependencia ou seguranca, fronteira de API versionada e estavel, necessidade operacional real e capacidade de manter o novo repositorio. Os nomes de responsabilidades associados a DP16/DP19 sao referencias de governanca futura, nao autorizacao para criar repositorios agora.

## Referencias

- [ADR-0001 - Repositorio inicial](../adr/0001-repo-inicial.md)
- [ADR-020 - FND-01](../adr/ADR-020-fnd01-catalogo-local.md)
- [README do repositorio](../../README.md)
- Jira `PDP` em <https://marqs.atlassian.net>
- Referencias de Confluence `DP16` e `DP19`, conforme o card Jira
