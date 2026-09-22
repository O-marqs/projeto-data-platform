# FND-02 - Matriz de versoes homologada

Esta matriz registra o conjunto usado pelo laboratorio do FND-01 e os artefatos
que precisam permanecer alinhados no FND-02. As imagens usam tags legiveis e
digests de manifest publicados no Docker Hub. Os digests abaixo foram
consultados em 2026-09-21; o Docker Desktop desta validacao executa imagens
`linux/amd64`.

## Caminho critico executado

| Componente | Versao fixa | Imagem/artefato | Digest ou checksum | Status |
| --- | --- | --- | --- | --- |
| RustFS | `1.0.0-alpha.81` | `rustfs/rustfs:1.0.0-alpha.81` | `sha256:4ee605dfe7c6548d1fa1856357e8a1eccd929e3176acf933fafeba3ce09a69f9` | Homologado |
| Apache Polaris | `1.7.0` | `apache/polaris:1.7.0` | `sha256:3495f67f38cca33892a045f7dd3f46eb52387f0fd52d4145538a772fd8aedad7` | Homologado |
| Polaris Admin Tool | `1.7.0` | `apache/polaris-admin-tool:1.7.0` | `sha256:3d8a24cea57aef3b71a0d7b09e5d2278d01e7e1b30071bf6648f2a6953322cca` | Homologado |
| PostgreSQL | `18.6` | `postgres:18.6` | `sha256:86c951e05bf56c93d95d397747fb8820ac76cc3bedb78f43abd83eedbe3666ae` | Homologado |
| Apache Spark | `3.5.9` | `apache/spark:3.5.9-java17-python3` | `sha256:f3d6eaa8bab8ec2e38f3c3918a5b2f8b253c95bcb19f9e87ad0e0cdacf9df2d5` | Homologado |
| Iceberg Spark runtime | `1.10.1` | `org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.10.1` | `sha256:39ea09e6c03550a300b9d9ab498949836d2d434e441da4c12a943a086e396940` | Homologado |
| Iceberg AWS bundle | `1.10.1` | `org.apache.iceberg:iceberg-aws-bundle:1.10.1` | `sha256:86bf20892ea5b4c17688f19b075399885f6aa5303f6b2dc9f491e76ceef9633b` | Homologado |
| AWS CLI bootstrap | `2.36.44` | `amazon/aws-cli:2.36.44` | `sha256:e8467f2c319f9bc9a1471808a69949a76915e9c95eaf4a09ece9f9e85fd32747` | Homologado |
| Catalog bootstrap curl | `8.22.0` | `alpine/curl:8.22.0` | `sha256:a39f52cab21d7e283448a9f73032dfb578ffcea9edaaa90c1d637117149b337f` | Homologado |

As referencias primarias sao [Polaris downloads](https://polaris.apache.org/downloads/),
[Polaris JDBC](https://polaris.apache.org/guides/jdbc/), [Spark downloads](https://spark.apache.org/downloads/),
[Iceberg Spark getting started 1.10.1](https://iceberg.apache.org/docs/1.10.1/spark-getting-started/)
e [Iceberg multi-engine support](https://iceberg.apache.org/multi-engine-support/).

## Runtime efetivo

- Java: Java 17, imposto pela tag `java17` da imagem Spark e exercitado no
  smoke test.
- Scala: 2.12, exigido pelo sufixo `_2.12` do runtime Iceberg selecionado.
- Python: `3.10.12`, fornecido pela imagem oficial
  `apache/spark:3.5.9-java17-python3` e confirmado pelo `spark-submit`.
- Dependencias Python do experimento: nenhuma dependencia adicional. O job
  usa somente a biblioteca PySpark ja presente na imagem Spark e a biblioteca
  padrao do Python. Nao ha `requirements.txt`, `pyproject.toml` ou lockfile
  Python aplicavel a este laboratorio.
- Dependencias Maven diretas: os dois JARs Iceberg acima. Os POMs publicados
  desses artefatos nao adicionam dependencias Maven transitivas; o AWS bundle
  e distribuido como bundle. O Spark/Iceberg continua dependendo das
  bibliotecas fornecidas pela propria imagem Spark.
- Resolucao Maven: `verify-iceberg-artifacts.py` baixa os dois artefatos a
  partir das coordenadas fixas, valida os SHA-256 esperados e somente depois
  o entrypoint passa os caminhos locais verificados ao `spark-submit` via
  `--jars`. Um arquivo presente no cache com checksum incorreto causa falha;
  nunca e sobrescrito silenciosamente. Um cache Maven local nao e requisito
  oculto: a primeira execucao precisa de Maven Central, e a evidencia deve
  registrar os casos de download e cache.

## Airflow e providers

Airflow e providers ficam fora do FND-02 executado. A tabela abaixo e apenas
planejamento de compatibilidade para uma etapa futura; nenhuma imagem, DAG ou
provider foi instalado ou homologado nesta tarefa.

Esta e uma decisao de sequenciamento: a selecao de Python, Airflow e providers
sera feita no card responsavel pelo primeiro pipeline orquestrado, quando o
executor e a conexao Spark estiverem definidos. O planejamento original foi
preservado, mas nao e tratado como homologacao deste laboratorio.

| Item | Planejamento | Status |
| --- | --- | --- |
| Apache Airflow | escolher uma linha suportada apos definir a politica de Python e constraints oficiais | Planejado |
| `apache-airflow-providers-apache-spark` | fixar junto com o arquivo de constraints da linha Airflow escolhida | Planejado |
| Executor/conexao Spark | definir quando o primeiro DAG for escopado | Planejado |

Nao e correto declarar Airflow compativel ou homologado a partir deste
laboratorio, porque nenhum DAG ou provider foi executado.

## Regras de reproducibilidade

- `latest` nao e utilizado.
- O Compose aplica digest por default mesmo quando um `.env` antigo nao possui
  as novas variaveis de digest.
- O bootstrap do catalogo usa apenas `curl` e utilitarios POSIX da imagem
  fixada; nao instala `jq` ou outro pacote em tempo de execucao.
- Os volumes padrao preservam a compatibilidade do FND-01. A validacao limpa
  usa nomes de volume e projeto Compose unicos, gerados por
  `scripts/fnd02-clean-validation.ps1`.
- Os digests sao manifest digests observados para `linux/amd64`; uma execucao
  em outra arquitetura precisa repetir a verificacao do manifesto e pode
  exigir um digest de plataforma diferente.
