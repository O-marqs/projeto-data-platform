# FND-01 - Matriz de versoes

As versoes abaixo foram fixadas em 16/09/2026 a partir da documentacao oficial e das imagens publicadas pelos projetos. O laboratorio nao usa `latest`.

| Componente | Versao | Imagem/runtime | Referencia oficial | Motivo |
| --- | --- | --- | --- | --- |
| RustFS | 1.0.0-alpha.81 | `rustfs/rustfs:1.0.0-alpha.81` | [Polaris Quickstart](https://polaris.apache.org/guides/quickstart/) | E a tag fixada usada pelo quickstart oficial atual de Polaris com RustFS. |
| Apache Polaris | 1.7.0 | `apache/polaris:1.7.0` | [Polaris releases](https://polaris.apache.org/downloads/) | Release atual documentada, com catalogo REST e backend JDBC. |
| Polaris Admin Tool | 1.7.0 | `apache/polaris-admin-tool:1.7.0` | [Polaris JDBC/Postgres guide](https://polaris.apache.org/guides/jdbc/) | Mesma release do servidor para bootstrap do realm persistente. |
| PostgreSQL | 18.6 | `postgres:18.6` | [Polaris JDBC/Postgres guide](https://polaris.apache.org/guides/jdbc/) | Versao fixada usada no exemplo oficial de persistencia JDBC; o volume segue o layout recomendado para PostgreSQL 18+. |
| Apache Spark | 3.5.9 | `apache/spark:3.5.9-java17-python3` | [Spark downloads](https://spark.apache.org/downloads) | Spark 3.5 e mantido pelo Iceberg e a imagem oficial combina Java 17 e Python 3. |
| Apache Iceberg | 1.10.1 | `iceberg-spark-runtime-3.5_2.12:1.10.1` | [Iceberg Spark getting started](https://iceberg.apache.org/docs/1.10.1/spark-getting-started/) | Runtime oficial para Spark 3.5/Scala 2.12; AWS bundle adiciona suporte S3. |
| Iceberg AWS bundle | 1.10.1 | `iceberg-aws-bundle:1.10.1` | [Iceberg multi-engine support](https://iceberg.apache.org/multi-engine-support/) | Bundle de storage necessario para o acesso S3-compatible. |

## Compatibilidade considerada

- Spark 3.5 usa Scala 2.12 na imagem escolhida; por isso o runtime e `iceberg-spark-runtime-3.5_2.12`.
- Spark 3.5 e compativel com Java 8/11/17; a imagem fixa `java17` para manter um runtime atual e reproduzivel.
- Iceberg documenta Spark 3.5 como mantido e lista 1.10.1 como runtime compativel no guia usado para o spike.
- Polaris documenta o fluxo REST com Spark e RustFS; o catalogo usa `endpoint` para clientes e `endpointInternal` para o servidor.
- O catalogo usa `stsUnavailable=true`, pois o laboratorio depende de credenciais estaticas do RustFS e nao implementa credential vending STS; o Spark recebe essas credenciais apenas via `.env` local.
