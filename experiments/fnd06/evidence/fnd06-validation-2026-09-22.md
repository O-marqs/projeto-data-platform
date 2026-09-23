# Evidencia FND-06 / PDP-24

## Ambiente

- Data da execucao: 2026-09-22.
- Sistema operacional: Windows com Docker Desktop e containers Linux.
- Shell: PowerShell.
- Docker Compose: v2.
- Branch: `feat/fnd06-identity-secrets-boundaries`.
- Base comparada: `origin/main` em `e7c2cd5`.
- Commit de codigo efetivamente validado: `7c7bff9c7652837620a5e7885dbd37b8b2434c51`.
- Ambiente de testes: projeto descartavel `pdp-fnd04-test`, database
  `control_test_db`, volume `pdp-fnd04-test_control_postgres_data`, portas
  `8001/5434`.
- Ambiente normal: projeto `pdp-fnd04`, database `control_db`, volume
  `pdp-fnd04_control_postgres_data`, portas `8000/5433`.
- Ambiente de upgrade: projeto descartavel `pdp-fnd06-upgrade-20260922`, com
  database, volume e porta exclusivos.

## Componentes e alteracoes validadas

- Allowlist plana de configuracao publica por tipo (`postgresql` e `s3`) no
  modelo, na aplicacao e em constraints PostgreSQL.
- Nova migration incremental `0004_connection_public_schema`; migrations
  anteriores nao foram alteradas.
- `SecretResolver` ancorado em uma Connection persistida, com autorizacao por
  dominio, permissao, workload e ID concreto da Connection.
- Compose fixa a revisao atual `0004_connection_public_schema`, impedindo que
  um `.env` antigo reduza silenciosamente a expectativa de readiness.
- README, threat model e testes atualizados.

## Criterios

| Criterio | Resultado | Evidencia |
| --- | --- | --- |
| `docker compose config --quiet` | PASS | Compose do Control Plane validado antes e depois das alteracoes |
| Suite completa FND-04/FND-06 | PASS | Duas execucoes independentes: `21 passed`, `1 warning` em cada |
| Allowlist publica por tipo | PASS | Somente campos documentados de PostgreSQL/S3 sao aceitos |
| Campo sensivel sob nome generico | PASS | `auth.value` sintetico rejeitado pela aplicacao e pelo modelo |
| Insercao SQL direta indevida | PASS | Constraint `ck_connections_config_public_allowlist` rejeitou JSON aninhado |
| Marcador secreto ausente da resposta HTTP | PASS | Testes de resposta autorizada e negada |
| Marcador ausente de logs e erros | PASS | Teste de erro de validacao retorna apenas `connection_config_invalid` |
| Negacao HTTP 403 | PASS | Permissoes ausentes, dominio cruzado e IDs fora do escopo |
| Resolver parte de Connection persistida | PASS | O contrato recebe `connection_id` e carrega o registro no Control DB |
| Resolver rejeita conexao cruzada | PASS | Identidade com permissao para outra Connection foi negada |
| Resolver exige workload concreto | PASS | Identidade sem `workload_id` nao atende o contrato |
| Configuracao legada `0001` | PASS | `Settings` normaliza revisoes legadas para a revisao atual |
| Readiness com migration pendente | PASS | Teste unitario e ambiente real responderam HTTP 503 |
| Upgrade incremental `0001 -> 0004` | PASS | Migration aplicada em ordem sem apagar a organizacao sintetica |
| Readiness apos upgrade | PASS | Ambiente de upgrade respondeu HTTP 200 |
| Dados preexistentes preservados no upgrade | PASS | `fnd06-upgrade-sentinel|active` permaneceu apos `alembic upgrade head` |
| Readiness do ambiente normal | PASS | `pdp-fnd04` respondeu HTTP 200 apos a migration |
| Sentinela do Control DB normal | PASS | `sentinel-fnd06-20260922-7d5a|active` permaneceu |
| Volume normal preservado | PASS | `pdp-fnd04_control_postgres_data` manteve `CreatedAt=2026-09-22T18:26:49Z` |
| Volumes FND-01 preservados | PASS | `pdp_fnd01_postgres_data` e `pdp_fnd01_rustfs_data` permaneceram presentes |
| Limpeza destrutiva no ambiente normal | PASS | Nao executado `down --volumes` no projeto normal |
| Credenciais reais versionadas | PASS | Apenas valores sinteticos em `.env.example` e testes |
| Vault/Keycloak/resolvedor real | NAO APLICAVEL | Explicitamente fora do FND-06 |

## Comandos e resultados

```powershell
docker compose --project-name pdp-fnd04 --env-file .env.example -f infra/local/control-plane/docker-compose.yml config --quiet
./scripts/fnd04.ps1 -Action up -EnvFile .env.example
./scripts/fnd04.ps1 -Action test -EnvFile .env.example
./scripts/fnd04.ps1 -Action test -EnvFile .env.example
./scripts/fnd04.ps1 -Action down -EnvFile .env.example
git diff --check
```

Os dois testes da suite criaram o projeto e o volume descartaveis, executaram
as 21 verificacoes e removeram somente esses recursos ao final.

Para o upgrade foi usado um projeto descartavel separado. O banco foi criado
na revisao `0001_initial_control_plane`, recebeu a organizacao sintetica
`fnd06-upgrade-sentinel`, respondeu HTTP 503 antes das migrations seguintes,
recebeu `0002`, `0003` e `0004` em ordem e respondeu HTTP 200 depois. A revisao
final foi `0004_connection_public_schema` e a organizacao continuou presente.

No ambiente normal, a migration foi aplicada sobre o volume existente. O
sentinela `sentinel-fnd06-20260922-7d5a` permaneceu `active`. O comando final
foi `down` sem `--volumes`, e o volume normal manteve o mesmo `CreatedAt`.

## Seguranca e limites

Os marcadores de segredo usados nos testes sao sinteticos e nao sao
reproduzidos nesta evidencia. O Control DB armazena somente `secret_ref` opaco;
nenhum valor secreto e retornado pela API. O resolvedor continua indisponivel
por desenho e falha explicitamente depois da autorizacao correta.

Nao foram executados E2E FND-01/FND-02, Vault, Keycloak, pipeline, cloud ou
Kubernetes. Esses itens estao fora do FND-06. Nao foi feito merge, nao houve
alteracao de status no Jira e o SEC-01 nao foi iniciado.

## Documentacao relacionada

- [README do Control Plane](../../../apps/control-plane-api/README.md)
- [Threat model do FND-06](../../../docs/security/fnd06-identity-secrets-threat-model.md)
