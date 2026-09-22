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
- Commit de codigo validado: `98afd5e544845e79710e80be822c2a4a288cdb77`.
- Projeto Compose de validacao: `pdp-fnd04-validation`.
- Configuracao: `.env.example`, somente com valores sinteticos.

## Componentes

| Componente | Versao/configuracao validada |
| --- | --- |
| FastAPI | 0.115.6 |
| Uvicorn | 0.34.0 |
| SQLAlchemy | 2.0.37 |
| Alembic | 1.14.1 |
| Python | 3.12.8 slim-bookworm |
| PostgreSQL Control DB | 18.6, imagem com digest fixado |
| Database | `control_db`, usuario `control_user`, porta local `5433` |
| API | porta local `8000`, bind em `127.0.0.1` |
| Volume | `pdp_control_postgres_data` |

O Control DB tem Compose, rede, credenciais, database, migration history e
volume separados do PostgreSQL usado pelo Polaris no FND-01. Nenhum arquivo de
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
| Persistência após restart | PASS | Registro `restart-validation` reencontrado após `down`, subida novamente e migration. |
| Isolamento FND-01/FND-02 | PASS | Projeto, rede, portas, volume e Compose dedicados; nenhum runtime anterior alterado. |
| E2E FND-01/FND-02 | NÃO EXECUTADO | Fora do escopo deste card; apenas isolamento/regressão estrutural foi verificado. |

O teste automatizado foi executado em container separado contra PostgreSQL real,
e não contra SQLite ou banco em memória. O script `scripts/fnd04.ps1 test`
reconstrói as imagens, sobe os serviços, reaplica a migration e executa os seis
testes.

## Persistência observada

1. O ambiente foi iniciado com volume novo.
2. Foi inserida uma Organization de validação com slug `restart-validation`.
3. O resultado observado foi `restart-validation|active`.
4. Os containers foram removidos com `down`, sem `--volumes`.
5. O ambiente foi iniciado novamente; a migration permaneceu em `head`.
6. A mesma Organization foi consultada novamente e retornou `restart-validation|active`.

Tempo medido para restart com imagem local disponível: aproximadamente 14,23 s,
incluindo build cacheado, readiness do PostgreSQL, migration e health da API.

## Consumo observado

Leitura pontual com `docker stats --no-stream` depois da subida:

| Serviço | CPU observado | Memória observada |
| --- | ---: | ---: |
| Control API | 0,19% | 57,38 MiB |
| Control PostgreSQL | 0,09% | 27,46 MiB |

Os valores são instantâneos, não peak histórico. Consumo de cold start e peak de
build não foi medido isoladamente nesta execução.

## Segurança e reprodutibilidade

- `.env` local não é versionado; somente `.env.example` é rastreado.
- O exemplo contém credenciais sintéticas de laboratório.
- A API não imprime senha, token, Authorization header ou connection string nas respostas de health.
- O build usa `.dockerignore` para não enviar `.env` ao contexto Docker.
- A imagem PostgreSQL usa versão e digest fixados; não há `latest` no Compose.
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
