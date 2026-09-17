# ADR-020 - Laboratorio local do FND-01

## Status

Aceito para o spike local; nao e uma decisao de producao.

## Contexto

O FND-01 precisa provar um caminho minimo e reproduzivel de PySpark/Spark SQL para tabelas Apache Iceberg, com Apache Polaris como catalogo REST e RustFS como object storage S3-compatible. A tabela e o catalogo precisam sobreviver a um restart do ambiente local.

## Alternativas consideradas

### Catalogo simples/local

Um catalogo local em memoria ou baseado em arquivos reduziria o numero de containers, mas nao prova o comportamento do catalogo centralizado que o backlog PDP pretende exercitar. O quickstart de Polaris com metastore em memoria tambem nao atende ao aceite de persistencia do estado do catalogo.

### Apache Polaris

Polaris e o catalogo Iceberg REST previsto no backlog e possui guia oficial de integracao com Spark, RustFS e persistencia JDBC. Foi escolhido para validar desde ja a fronteira que a plataforma pretende manter.

### Object storage

RustFS foi escolhido como storage S3-compatible local. Ele oferece endpoint S3, console e volume persistente, e aparece no guia oficial de Polaris para esse fluxo.

## Decisao

Usar um Compose incremental com:

- RustFS 1.0.0-alpha.81 e volume nomeado para os objetos.
- PostgreSQL 18.6 e volume nomeado para a persistencia JDBC do Polaris.
- Polaris 1.7.0 e `apache/polaris-admin-tool:1.7.0` para bootstrap.
- Spark 3.5.9 com Java 17, Iceberg 1.10.1 e Scala 2.12.
- Catalogo `fnd01_catalog`, namespace `lab` e tabela `lab.fnd01_test`.
- `stsUnavailable=true` e credenciais estaticas de desenvolvimento, pois o spike nao implementa STS; o Spark recebe as credenciais por variaveis do `.env` local.

O experimento fica isolado em `experiments/fnd01/` e a infraestrutura em `infra/local/`; nenhuma parte e promovida ainda para um Control Plane ou pipeline de producao.

## Consequencias

### Positivas

- O caminho Spark -> Iceberg -> Polaris -> RustFS e exercitado com componentes reais.
- A persistencia do catalogo e dos dados pode ser demonstrada com `stop`/`up` sem remover volumes.
- As imagens e dependencias criticas estao fixadas e documentadas.
- O bootstrap do bucket e do catalogo e idempotente para facilitar repeticao.

### Limitacoes

- O metastore e o object storage sao instancias locais unicas.
- A autenticacao usa credenciais estaticas e o catalogo nao usa STS.
- A imagem RustFS esta em release alpha; a escolha precisa ser reavaliada antes de compartilhar o ambiente.
- A execucao depende de acesso a Docker Hub e Maven Central na primeira subida.

## Migracao

Nao existe migracao de catalogo nesta etapa. O repositorio anterior continha apenas estrutura e documentacao; o FND-01 adiciona o primeiro laboratorio executavel mantendo a decisao de monorepo do ADR-0001.

## Evidencia esperada

O aceite exige `docker compose config`, healthchecks verdes, escrita/leitura Spark, objetos no bucket e leitura bem-sucedida apos `docker compose stop` seguido de nova subida. Se o ambiente nao conseguir executar Docker ou baixar dependencias, o resultado deve ser reportado como `IMPLEMENTADO, MAS NÃO EXECUTADO`.
