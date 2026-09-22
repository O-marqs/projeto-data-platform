# Control Plane API

Base executavel do Control Plane criada no FND-04/PDP-22. Esta entrega fornece uma API FastAPI minima, um banco PostgreSQL dedicado, migrations Alembic e endpoints de health/readiness. Ela nao implementa o Control Plane completo nem endpoints de dominio.

## Escopo implementado

- `GET /health/live`: responde quando o processo HTTP esta vivo, sem consultar o banco.
- `GET /health/ready`: consulta o Control DB e exige a migration `0001_initial_control_plane` aplicada.
- Modelo relacional minimo: Organization, Domain, Team e DataProduct.
- UUIDs internos, foreign keys e unicidade por escopo no PostgreSQL.
- Migration versionada em `alembic/versions/`.
- Testes HTTP e constraints executados contra PostgreSQL real no Compose.

Nao implementado: CRUD, autenticacao, autorizacao, membership, RBAC, datasets, pipelines, runs, contratos, auditoria, outbox, workers ou integracao com Polaris.

## Estrutura

```text
apps/control-plane-api/
  app/
    config.py       configuracao tipada por ambiente
    db.py           engine e sessoes SQLAlchemy
    models.py       modelo relacional do FND-04
    main.py         composicao FastAPI e health/readiness
  alembic/
    env.py
    versions/       migrations versionadas
  tests/            testes HTTP e constraints PostgreSQL
  Dockerfile
  requirements.txt
  alembic.ini
```

O dominio ainda nao foi extraido para uma biblioteca independente. A implementacao e intencionalmente pequena: a API faz composicao, o adapter SQLAlchemy acessa o banco e as regras de unicidade ficam protegidas por constraints reais.

## Pre-requisitos

- Git.
- Docker Desktop com Docker Compose v2.
- PowerShell.
- `.env` local criado a partir de `.env.example`.

## Configuracao

As variaveis `CONTROL_*` ficam no `.env.example`. A conexao do Control Plane e independente do Polaris:

- Database: `control_db`.
- Usuario: `control_user`.
- Volume: `pdp-fnd04_control_postgres_data` por padrao, escopado ao projeto Compose.
- Porta local do banco: `5433` por padrao.
- Porta local da API: `8000` por padrao.

Os valores do exemplo sao sinteticos e exclusivos do desenvolvimento local. A aplicacao recebe `CONTROL_DATABASE_URL` por ambiente e nao usa host, porta, usuario ou senha do PostgreSQL do Polaris como fallback.

## Subir somente o Control Plane

```powershell
Copy-Item .env.example .env
./scripts/fnd04.ps1 up
```

O FND-04 usa o Compose `infra/local/control-plane/docker-compose.yml`, com projeto separado, rede separada e volume proprio. Nao e necessario nem desejavel compartilhar rede com o Compose do FND-01. O script usa `--build` para que alteracoes locais no app nao sejam mascaradas por uma imagem antiga.

## Migrations

As migrations sao explicitas e executadas pelo servico `control-migrate`; a API nao cria tabelas automaticamente.

```powershell
./scripts/fnd04.ps1 up
docker compose --project-name pdp-fnd04 --env-file .env -f infra/local/control-plane/docker-compose.yml run --rm control-migrate
docker compose --project-name pdp-fnd04 --env-file .env -f infra/local/control-plane/docker-compose.yml run --rm control-migrate alembic current
```

Uma migration reaplicada no mesmo banco nao altera o schema quando a versao ja esta atual. Em caso de falha, preserve o volume, consulte `docker compose ... logs control-migrate`, corrija a causa e execute novamente o servico de migration. Nao execute downgrade destrutivo no volume persistente real; para uma instalacao limpa use `./scripts/fnd04.ps1 clean`, que remove somente o volume do Control Plane.

## Testes

```powershell
./scripts/fnd04.ps1 test
```

O comando inicia o banco e a API, reaplica a migration para provar idempotencia e executa os testes em um container separado. Os testes cobrem liveness, readiness, indisponibilidade do banco, unicidade de Domain, Team e DataProduct e foreign keys obrigatorias.

## Health e readiness

```powershell
Invoke-WebRequest http://127.0.0.1:8000/health/live
Invoke-WebRequest http://127.0.0.1:8000/health/ready
```

- `200` em `/health/live`: processo HTTP respondendo.
- `200` em `/health/ready`: banco acessivel e migration atual aplicada.
- `503` em `/health/ready`: banco indisponivel ou migrations ausentes/desatualizadas.

As respostas nao exibem connection string, senha ou detalhes internos do banco.

## Logs, parada e limpeza

```powershell
docker compose --project-name pdp-fnd04 --env-file .env -f infra/local/control-plane/docker-compose.yml logs control-api control-migrate
./scripts/fnd04.ps1 down
./scripts/fnd04.ps1 clean
```

`down` remove apenas os containers do projeto FND-04 e preserva `pdp-fnd04_control_postgres_data`. `clean` remove apenas o volume escopado ao projeto em uso. Nenhum desses comandos usa o projeto Compose, volume ou container do FND-01/FND-02. Ao usar um `ProjectName` alternativo, o Compose cria um volume igualmente escopado a esse projeto.

## Portabilidade e limitacoes

O Control Plane depende somente de `CONTROL_DATABASE_URL` e de seu schema/migrations. Hoje ele usa uma instância PostgreSQL em container separado do Polaris para reduzir acoplamento local. No futuro, os databases podem compartilhar uma instância PostgreSQL, mantendo usuarios, databases e migrations independentes; isso nao foi implantado nem homologado em nuvem neste card.

As foreign keys usam a politica padrao restritiva do PostgreSQL: nao ha `ON DELETE CASCADE` na migration. A remocao de uma Organization ou Domain com dependentes deve ser tratada explicitamente por uma futura capability de governanca; esta base nao apaga dados em cascata.

A API e destinada ao laboratorio local. Nao ha autenticacao, autorizacao, TLS, rede publica ou garantia de seguranca para exposicao na internet.
