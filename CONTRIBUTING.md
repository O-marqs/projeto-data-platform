# Contribuindo

Este repositorio e um monorepo. Criar uma pasta reservada nao significa criar uma capability: cada componente so deve ganhar codigo quando houver um caso de uso, contrato, teste e responsabilidade claros.

## Pre-requisitos locais

Use Git, Docker Desktop com Compose v2 e PowerShell. Copie `.env.example` para `.env` quando precisar executar o laboratorio. O arquivo `.env` e local e nunca deve ser commitado. Use apenas credenciais sinteticas ou de desenvolvimento.

## Fluxo Jira

1. Escolha uma issue do projeto `PDP` e confirme o escopo no backlog.
2. Mantenha o identificador da issue na branch, no commit, no PR e na evidencia quando houver.
3. Registre decisoes de arquitetura em `docs/adr/` e resultados verificaveis junto ao experimento ou componente correspondente.

## Branches e commits

Use nomes curtos, minusculos e separados por hifens:

```text
feat/fnd03-monorepo-conventions
fix/fnd01-persistence-check
docs/fnd03-architecture-rules
```

Prefira commits no formato `<tipo>(<card>): <acao curta>`:

```text
docs(fnd03): documentar limites do monorepo
fix(fnd01): tornar verify nao destrutivo
```

Nao ha uma ferramenta de commit obrigatoria no momento. O importante e que o historico seja legivel e rastreavel.

## Organizacao e dependencias

- `apps/` deve conter composicao e interfaces de aplicacao, nao regras de dominio espalhadas.
- `libs/platform-contracts/` e a casa reservada para contratos, schemas e compatibilidade compartilhados.
- `pipelines/` deve conter jobs e transformacoes de dados com fixture, rerun e recuperacao descritos.
- `experiments/` abriga spikes reproduziveis e suas evidencias; nao e dependencia de producao.
- `infra/` abriga ambiente e integracoes operacionais.
- `tests/` abriga testes e fixtures; evidencias de laboratorio ficam junto do experimento.
- Um futuro `core` ou biblioteca de dominio deve permanecer neutro de Spark, Airflow, FastAPI, Kubernetes e SDKs de provedores. Adaptadores e runtimes dependem das portas internas, nunca o contrario.

O repositorio ainda nao possui codigo de `core`, dominio ou casos de uso. Nao crie um pacote vazio apenas para preencher a arvore.

## Ambiente e laboratorios

Para o FND-01:

```powershell
Copy-Item .env.example .env
./scripts/fnd01.ps1 up
./scripts/fnd01.ps1 test
./scripts/fnd01.ps1 down
```

`down` preserva volumes. O comando de limpeza remove dados e deve ser usado explicitamente para validar instalacao limpa. Nao altere volumes persistentes durante um teste de restart.

## Evidencia, testes e documentacao

- Escolha testes proporcionais ao risco da mudanca.
- Para alteracoes de runtime, registre comandos, resultado, evidencia, tempos, consumo e limitacoes.
- Para alteracoes documentais, execute pelo menos verificacao de diff, links e caminhos referenciados.
- Nao declare um smoke test como prova de persistencia se a etapa de verify recria namespace, tabela ou dados.
- Nao salve tokens, senhas, chaves, headers de autorizacao ou dumps sem redaction.
- Atualize README, runbook, matriz de versoes ou ADR quando a mudanca afetar seu contrato.

## ADRs

Crie ou atualize um ADR quando a mudanca atravessar limites de componente, alterar storage/catalogo/runtime, introduzir uma convencao de contrato, mudar seguranca ou alterar estado operacional. Uma reorganizacao documental local ou um nome de pasta nao exige ADR, salvo quando mudar uma decisao arquitetural existente.

## Pull requests

O PR deve informar objetivo e card Jira, arquivos alterados, testes executados, evidencia versionada, limitacoes reais e testes nao executados. Nao inclua servicos, frameworks ou repositorios fora do escopo da issue.

## Definition of Done

- Criterios de aceite demonstrados ou explicitamente marcados como nao executados.
- Testes proporcionais ao risco concluidos.
- Evidencia ligada ao commit quando houver validacao operacional.
- Documentacao e ADR atualizados quando aplicavel.
- Segredos fora do Git e `.env` ausente dos arquivos rastreados.
- Revisao do owner indicada em `.github/CODEOWNERS` concluida.

## Responsabilidade de revisao

`.github/CODEOWNERS` define o revisor padrao do repositorio. Isso e uma regra de revisao tecnica e nao atribui automaticamente papeis de Data Owner, Technical Owner ou ownership de Data Product.
