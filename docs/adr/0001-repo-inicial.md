# ADR 0001 - Repositorio inicial monorepo

## Status

Adotado para o estagio inicial do projeto

## Contexto

O backlog Jira do projeto PDP descreve uma plataforma com partes fortemente relacionadas: fundacao de engenharia, pipelines batch, lakehouse, control plane, portal, contratos, qualidade, governanca e observabilidade.

No estagio inicial, separar repositorios por area aumentaria o custo de coordenacao antes de existirem limites tecnicos comprovados.

## Decisao

Adotar, para o estagio inicial do projeto, um monorepo local com areas explicitas para:

- `apps/`
- `pipelines/`
- `libs/`
- `infra/`
- `docs/`
- `tests/`

## Consequencias

- A rastreabilidade entre Jira, codigo e documentacao fica mais simples no inicio.
- O CI pode evoluir por caminho afetado.
- A decisao nao e uma obrigacao permanente de manter todas as areas no mesmo repositorio.
- Limites futuros podem virar repositorios separados se houver necessidade real de ownership independente, ciclo de release ou seguranca, conforme os criterios abaixo.

## Criterios de revisao e eventual separacao

A separacao deve ser reavaliada quando houver uma fronteira tecnica estavel e beneficio operacional concreto, especialmente se existirem:

- ownership independente;
- ciclo de release ou deploy independente;
- necessidade de isolamento de dependencias ou seguranca;
- API ou contrato versionado e estavel;
- necessidade operacional real e capacidade de manter o novo repositorio.

Enquanto esses criterios nao forem demonstrados, o monorepo permanece a organizacao preferencial do estagio inicial, sem impedir uma decisao futura diferente.
