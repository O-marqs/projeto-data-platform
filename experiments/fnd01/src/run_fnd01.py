import argparse
import os
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark.sql.types import LongType, StringType, StructField, StructType, TimestampType


EXPECTED_ROWS = [
    (1, "Lucas", datetime(2026, 9, 16, 0, 0, 0)),
    (2, "Teste", datetime(2026, 9, 16, 0, 0, 1)),
    (3, "Iceberg", datetime(2026, 9, 16, 0, 0, 2)),
]
EXPECTED_VALUES = [
    (1, "Lucas", "2026-09-16 00:00:00"),
    (2, "Teste", "2026-09-16 00:00:01"),
    (3, "Iceberg", "2026-09-16 00:00:02"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="FND-01 Spark/Iceberg smoke test")
    parser.add_argument("--mode", choices=("write-read", "verify"), default="write-read")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    catalog = os.environ.get("ICEBERG_CATALOG", "polaris")
    namespace = os.environ.get("ICEBERG_NAMESPACE", "lab")
    table_name = os.environ.get("ICEBERG_TABLE", "fnd01_test")
    table = f"{catalog}.{namespace}.{table_name}"
    spark = SparkSession.builder.appName("pdp-fnd01").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    try:
        if args.mode == "write-read":
            spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {catalog}.{namespace}")
            spark.sql(
                f"""CREATE TABLE IF NOT EXISTS {table} (
                    id BIGINT,
                    name STRING,
                    created_at TIMESTAMP
                ) USING iceberg"""
            )
            existing_count = spark.sql(f"SELECT COUNT(*) AS count FROM {table}").first()[0]
            if existing_count == 0:
                schema = StructType(
                    [
                        StructField("id", LongType(), nullable=False),
                        StructField("name", StringType(), nullable=False),
                        StructField("created_at", TimestampType(), nullable=False),
                    ]
                )
                spark.createDataFrame(EXPECTED_ROWS, schema).writeTo(table).append()
                print("FND01_WRITE=PASS rows=3")
            else:
                print(f"FND01_WRITE=PASS existing_rows={existing_count}")

        namespaces = {
            row.namespace for row in spark.sql(f"SHOW NAMESPACES IN {catalog}").collect()
        }
        if namespace not in namespaces:
            raise RuntimeError(f"namespace {namespace} was not found")

        tables = {
            row.tableName for row in spark.sql(f"SHOW TABLES IN {catalog}.{namespace}").collect()
        }
        if table_name not in tables:
            raise RuntimeError(f"table {table_name} was not found in {catalog}.{namespace}")

        rows = [
            tuple(row)
            for row in spark.sql(
                f"SELECT id, name, date_format(created_at, 'yyyy-MM-dd HH:mm:ss') AS created_at "
                f"FROM {table} ORDER BY id"
            ).collect()
        ]
        if rows != EXPECTED_VALUES:
            raise RuntimeError(f"unexpected table contents: {rows}")

        print(f"FND01_NAMESPACE=PASS name={namespace} persisted={args.mode == 'verify'}")
        print(f"FND01_TABLE=PASS name={table}")
        print(f"FND01_READ=PASS rows={len(rows)}")
        if args.mode == "verify":
            print("FND01_RESTART_READ=PASS table_and_data_persisted=true")
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
