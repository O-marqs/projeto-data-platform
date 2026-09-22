# Evidencia FND-04 / PDP-22

## Escopo

Validacao da base FastAPI do Control Plane, do Control DB dedicado, da primeira
 migration Alembic, do modelo relacional minimo e dos endpoints de liveness e
 readiness. Esta evidencia nao declara CRUD, autenticacao, RBAC, pipelines,
 portal ou o Control Plane completo como implementados.

## Ambiente

- Sistema operacional: Windows com Docker Desktop e backend Linux containers.
- Shell: PowerShell.
- Docker Compose: v2, validado por `docker compose config`.
- Data da execucao: 2026-09-21.
- Commit de codigo validado: `1ecf4bc376293c753922137444cd112607c09001`.
- Projeto Compose de validacao: `pdp-fnd04-validation`.
- Configuracao: `.env.example`, somente com valores sinteticos.

## Componentes

| Componente | Versao/configuracao validada |
| --- | --- |
| FastAPI | 0.115.6 |
| Uvicorn | 0.34.0 |
| SQLAlchemy | 2.0.37 |
| Alembic | 1.14.1 |
| Python | 3.12.8 slim-bookworm, digest `sha256:2199a62885a12290dc9c5be3ca0681d367576ab7bf037da120e564723292a2f0` |
| PostgreSQL Control DB | 18.6, imagem com digest fixado |
| Database | `control_db`, usuario `control_user`, porta local `5433` |
| API | porta local `8000`, bind em `127.0.0.1` |
| Volume | `pdp-fnd04_control_postgres_data` por padrao, escopado ao projeto Compose |

O Control DB tem Compose, rede, credenciais, database, migration history e
volume escopados ao projeto, separados do PostgreSQL usado pelo Polaris no FND-01. Nenhum arquivo de
runtime do FND-01 ou FND-02 foi alterado.

## Testes

| Teste | Resultado | Evidencia resumida |
| --- | --- | --- |
| `docker compose config` | PASS | Compose do Control Plane processado sem erro. |
| Subida limpa do Control DB | PASS | Volume dedicado criado em projeto separado. |
| PostgreSQL health | PASS | `control-db` ficou `healthy`. |
| Migration inicial | PASS | `0001_initial_control_plane` aplicada. |
| Migration reaplicada | PASS | Execucao repetida terminou sem alterar schema. |
| Alembic current | PASS | `0001_initial_control_plane (head)`. |
| API health/liveness | PASS | `/health/live` respondeu HTTP 200 sem consultar DB. |
| API readiness | PASS | `/health/ready` respondeu HTTP 200 com DB e migration atuais. |
| Readiness sem banco | PASS | Teste automatizado respondeu HTTP 503 sem segredo ou connection string. |
| Organization | PASS | Tabela criada e usada pelos testes de constraints. |
| Domain | PASS | FK para Organization e slug único por organização. |
| Team | PASS | FK para Organization e slug único por organização. |
| DataProduct | PASS | FK para Domain e slug único por domínio. |
| Foreign keys | PASS | Inserção órfã rejeitada pelo PostgreSQL. |
| Testes automatizados | PASS | `6 passed`, `1 warning` de depreciação do Starlette/AnyIO. |
| Persistência após restart | PASS | Registro `final-review-20260922` reencontrado após `down`, subida novamente e migration. |
| Isolamento FND-01/FND-02 | PASS | Projeto, rede, portas, volume e Compose dedicados; nenhum runtime anterior alterado. |
| E2E FND-01/FND-02 | NÃO EXECUTADO | Fora do escopo deste card; apenas isolamento/regressão estrutural foi verificado. |

O teste automatizado foi executado em container separado contra PostgreSQL real,
e não contra SQLite ou banco em memória. O script `scripts/fnd04.ps1 test`
reconstrói as imagens, sobe os serviços, reaplica a migration e executa os seis
testes.

## Persistência observada

1. O ambiente foi iniciado com volume novo escopado ao projeto Compose.
2. Foi inserida uma Organization de validação com slug `restart-validation`.
3. O resultado observado foi `restart-validation|active`.
4. Os containers foram removidos com `down`, sem `--volumes`.
5. O ambiente foi iniciado novamente; a migration permaneceu em `head`.
6. A mesma Organization foi consultada novamente e retornou `restart-validation|active`.

Tempo medido para restart com imagem local disponível: aproximadamente 10,76 s,
incluindo build cacheado, readiness do PostgreSQL, migration e health da API.

## Consumo observado

Leitura pontual com `docker stats --no-stream` depois da subida:

| Serviço | CPU observado | Memória observada |
| --- | ---: | ---: |
| Control API | 0,20% | 57,37 MiB |
| Control PostgreSQL | 0,09% | 25,97 MiB |

Os valores são instantâneos, não peak histórico. Consumo de cold start e peak de
build não foi medido isoladamente nesta execução.

## Segurança e reprodutibilidade

- `.env` local não é versionado; somente `.env.example` é rastreado.
- O exemplo contém credenciais sintéticas de laboratório.
- A API não imprime senha, token, Authorization header ou connection string nas respostas de health.
- O build usa `.dockerignore` para não enviar `.env` ao contexto Docker.
- As imagens Python e PostgreSQL usam versão e digest fixados; não há `latest` no Compose.
- As portas locais são bindadas em `127.0.0.1`; não há exposição pública ou autenticação neste card.

## Migration e recuperação

As migrations são explícitas e executadas pelo serviço `control-migrate`; a API
não usa `create_all`. A migration inicial possui downgrade destrutivo e não deve
ser executada no volume persistente real. Para laboratório descartável, use
`./scripts/fnd04.ps1 clean`, que remove somente o volume do FND-04. Para falha
de aplicação, preserve o volume, consulte os logs, corrija a migration e rode
novamente o serviço de migration.

## Limitações reais

- Não há CRUD, autenticação, autorização, RBAC, membership, contratos, datasets,
  pipelines, workers ou integração com Polaris.
- O modelo mínimo ainda não foi extraído para um `core` independente; não existe
  teste de isolamento de core aplicável.
- A configuração foi validada em Windows/Docker Desktop; Linux/macOS e execução
  fora de containers não foram homologados nesta evidência.
- O banco não deve ser exposto fora do host local sem controles adicionais.

## Revisão independente de 2026-09-22

O PR foi revalidado contra `origin/main` com a branch em `e1a1283` antes dos
ajustes finais. A instalação limpa foi repetida em um projeto Compose descartável
`pdp-fnd04-final-20260922`, com volume `pdp-fnd04-final-20260922_control_postgres_data`; o volume
`pdp_fnd01_postgres_data` permaneceu separado e não foi alterado.

| Critério do PDP-22 | Resultado |
| --- | --- |
| Monorepo e área FastAPI correta | PASS |
| Control DB, volume, credenciais e Compose isolados | PASS |
| Polaris PostgreSQL/schema não reutilizado | PASS |
| Modelo, foreign keys e unicidade no banco real | PASS |
| Migration em banco vazio e versão esperada | PASS |
| Reexecução idempotente da migration | PASS |
| API sem `create_all` ou alteração destrutiva no startup | PASS |
| Liveness sem banco | PASS |
| Readiness com banco disponível | PASS |
| Readiness com banco indisponível | PASS, HTTP 503 |
| Persistência após parada e reinicialização | PASS, registro recuperado |
| Links, caminhos e comandos documentados | PASS |
| `docker compose config` | PASS |
| `git diff --check` | PASS |
| Segredos reais versionados | PASS, nenhum encontrado |
| E2E dos laboratórios FND-01/FND-02 | NÃO EXECUTADO |
| Exposição pública, autenticação e cloud | NÃO APLICÁVEL ao FND-04 |

Resultados medidos nesta revisão:

- Testes automatizados: `6 passed`, uma advertência de depreciação externa do Starlette/AnyIO.
- Readiness com o banco parado: HTTP 503; após reiniciar o banco: HTTP 200.
- Restart `down`/`up` preservando volume: aproximadamente 10,76 s.
- Registro persistido: `final-review-20260922|active`.
- Consumo instantâneo: API 57,37 MiB e 0,20% CPU; PostgreSQL 25,97 MiB e 0,09% CPU.
- Commit de código validado nesta revisão: `1ecf4bc376293c753922137444cd112607c09001`.

### Correções realizadas durante a revisão

- `52bc087`: imagem Python fixada por digest e política de exclusão documentada.
- `5851c1e`: volume Control DB alterado de nome global fixo para volume escopado ao projeto Compose.
- `1ecf4bc`: timeout de conexão PostgreSQL limitado para falhas de readiness previsíveis.

Pendências não bloqueantes: a validação foi feita em Windows/Docker Desktop e
não homologa Linux/macOS ou implantação em nuvem. O PR não implementa CRUD,
autenticação, RBAC, pipelines, portal ou FND-05.
