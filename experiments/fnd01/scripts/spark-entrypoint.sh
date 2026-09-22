#!/bin/sh
set -eu

python3 /opt/fnd01/verify-iceberg-artifacts.py \
  --cache-dir /tmp/fnd01-maven-cache \
  --paths-file /tmp/fnd01-jar-paths

jar_paths=$(tr '\n' ',' < /tmp/fnd01-jar-paths | sed 's/,$//')

exec /opt/spark/bin/spark-submit \
  --jars "${jar_paths}" \
  --conf "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}=org.apache.iceberg.spark.SparkCatalog" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.type=rest" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.rest.auth.type=oauth2" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.uri=${POLARIS_INTERNAL_ENDPOINT}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.oauth2-server-uri=${POLARIS_INTERNAL_ENDPOINT}/v1/oauth/tokens" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.token-refresh-enabled=false" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.rest-metrics-reporting-enabled=false" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.warehouse=${POLARIS_CATALOG}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.credential=${POLARIS_ROOT_CLIENT_ID}:${POLARIS_ROOT_CLIENT_SECRET}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.scope=PRINCIPAL_ROLE:ALL" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.header.Polaris-Realm=${POLARIS_REALM}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.s3.endpoint=${RUSTFS_ENDPOINT}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.s3.path-style-access=true" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.s3.access-key-id=${RUSTFS_ACCESS_KEY}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.s3.secret-access-key=${RUSTFS_SECRET_KEY}" \
  --conf "spark.sql.catalog.${ICEBERG_CATALOG}.client.region=${RUSTFS_REGION}" \
  --conf "spark.sql.defaultCatalog=${ICEBERG_CATALOG}" \
  --conf "spark.driver.extraJavaOptions=-Divy.cache.dir=/tmp -Divy.home=/tmp" \
  /opt/fnd01/run_fnd01.py "$@"
