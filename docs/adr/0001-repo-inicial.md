# ADR 0001 - Repositorio inicial monorepo

## Status

Proposto

## Contexto

O backlog Jira do projeto PDP descreve uma plataforma com partes fortemente relacionadas: fundacao de engenharia, pipelines batch, lakehouse, control plane, portal, contratos, qualidade, governanca e observabilidade.

No momento inicial, separar repositorios por area aumentaria o custo de coordenacao antes de existirem limites tecnicos comprovados.

## Decisao

Criar um monorepo local com areas explicitas para:

- `apps/`
- `pipelines/`
- `libs/`
- `infra/`
- `docs/`
- `tests/`

## Consequencias

- A rastreabilidade entre Jira, codigo e documentacao fica mais simples no inicio.
- O CI pode evoluir por caminho afetado.
- Limites futuros podem virar repositorios separados se houver necessidade real de ownership, ciclo de release ou seguranca.
