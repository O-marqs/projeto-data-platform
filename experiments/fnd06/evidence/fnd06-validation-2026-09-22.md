# Evidência FND-06 / PDP-24

## Ambiente

- Sistema operacional: Windows com Docker Desktop e containers Linux.
- Shell: PowerShell.
- Compose: Docker Compose v2.
- Branch: `feat/fnd04-fastapi-control-db-migrations`.
- Base atualizada: `origin/main` em `e7c2cd5` antes da implementação.
- Commit de código validado: `5e5249a96b564cb3212a965560d8544a7880a548`.
- Ambiente de testes: projeto descartável `pdp-fnd04-test`, database
  `control_test_db`, volume `pdp-fnd04-test_control_postgres_data`.
- Ambiente normal: projeto `pdp-fnd04`, database `control_db`, volume
  `pdp-fnd04_control_postgres_data`.

## Componentes alterados

- Modelo SQLAlchemy `Connection` e validação de configuração/`secret_ref`.
- Migration Alembic `0002_connection`, encadeada após `0001_initial_control_plane`.
- Endpoint protegido `GET /connections/{id}`.
- Fronteira de identidade confiável e contrato sem resolvedor real de segredos.
- Testes de autorização, constraints, respostas e logs.
- README e threat model.

## Resultados

| Critério | Resultado | Evidência |
| --- | --- | --- |
| Migration nova preserva `0001` | PASS | `alembic_version=0002_connection` no volume normal existente |
| Migration funciona em instalação limpa | PASS | Suíte Compose descartável criou schema do zero |
| Connection pertence a Domain | PASS | foreign key e teste de domínio |
| Unicidade por domínio | PASS | `uq_connections_domain_name` e teste negativo |
| `secret_ref` opaco persiste sem valor secreto | PASS | formato `sref_...`, sem campo na resposta |
| Configuração pública rejeita material sensível | PASS | chaves e connection string sintética rejeitadas |
| Identidade autorizada lê Connection | PASS | HTTP 200 no mesmo domínio |
| Identidade sem permissão é negada | PASS | HTTP 403 |
| Outro domínio é negado por ID direto | PASS | HTTP 403 |
| Requisição sem identidade confiável é negada | PASS | HTTP 401 |
| Headers de identidade forjados não funcionam | PASS | headers `X-*` ignorados |
| `connection:admin` pode ler; resolve não lê | PASS | matriz de permissões |
| Resposta não contém secret_ref/segredo | PASS | teste de contrato HTTP |
| Logs não contêm marcador secreto | PASS | teste com header sintético e `caplog` |
| `./scripts/fnd04.ps1 test` | PASS | `15 passed`, 1 warning externo |
| Execução contra Compose normal é bloqueada | PASS | exit code `1` no fixture antes dos DELETEs |
| Sentinela normal preservado | PASS | `sentinel-fnd06-20260922-7d5a|active` após a suíte |
| Volume normal preservado | PASS | `pdp-fnd04_control_postgres_data`, criado em `2026-09-22T18:26:49Z` |
| Volumes FND-01 preservados | PASS | `pdp_fnd01_postgres_data` e `pdp_fnd01_rustfs_data` sem alteração |

## Comandos executados

```powershell
git fetch origin main
git merge origin/main
docker compose --env-file .env.example -f infra/local/control-plane/docker-compose.yml config --quiet
./scripts/fnd04.ps1 -Action up -ProjectName pdp-fnd04 -EnvFile .env.example
./scripts/fnd04.ps1 -Action test -EnvFile .env.example
docker compose --project-name pdp-fnd04 --env-file .env.example -f infra/local/control-plane/docker-compose.yml --profile test run --build --rm control-api-test pytest -q tests/test_connections.py
git diff --check
```

O comando forçado contra o projeto normal falhou deliberadamente no fixture
com a mensagem de isolamento `CONTROL_APP_ENV=test`/`control_test_db`; o
sentinela continuou presente e nenhum `DELETE` foi executado contra o Control DB
normal.

## Identidade e segredos

Os testes usam identidades sinteticas injetadas via `dependency_overrides` no
processo de teste. O ambiente HTTP normal nao possui essa substituicao. Os
valores de segredo usados nos testes nao sao reproduzidos nesta evidencia.
Keycloak, Vault, login humano e resolução real de segredo estão explicitamente
fora do FND-06.

## Itens não executados

- Confluence DP 03/05/07/14/16/22: indisponível neste ambiente de execução.
- Jira PDP-24/PDP-105/PDP-39: páginas não acessíveis pelo conector/browser
  disponível; contratos futuros foram tratados apenas pelos limites fornecidos
  no card.
- E2E FND-01/FND-02: não necessário para esta mudança e não executado.
- Keycloak, Vault, pipeline pessoal, cloud e Kubernetes: fora do escopo.

## Threat model

Consultar [o threat model do FND-06](../../../docs/security/fnd06-identity-secrets-threat-model.md).
