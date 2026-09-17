# Infra Local

Ambiente local do experimento `FND-01`.

Componentes ativos:

- `rustfs`: object storage S3-compatible com volume persistente.
- `postgres`: persistencia JDBC do Polaris com volume persistente.
- `polaris-bootstrap`: inicializacao do realm e credencial administrativa.
- `polaris`: catalogo REST Iceberg.
- `polaris-catalog-init`: criacao idempotente do catalogo apontando para RustFS.
- `spark`: servico sob demanda para o experimento PySpark/Iceberg.

O Compose esta em [docker-compose.yml](docker-compose.yml). Os volumes sao nomeados e sobrevivem a `docker compose down`; use `down -v` somente para limpar o laboratorio inteiro.
