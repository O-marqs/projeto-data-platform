# Pipelines Batch

Area reservada para o primeiro pipeline batch reproduzivel.

Fluxo alvo do MVP 01:

```text
PostgreSQL -> Bronze Iceberg -> Silver Iceberg -> Gold Iceberg
```

Requisitos de implementacao:

- Rerun sem duplicacao final.
- Fixture verificavel.
- Falha e recuperacao demonstradas.
- Evidencias ligadas ao Jira e ao commit.
