# Evidencia SEC-01 / PDP-105

## Identificacao

- Data da execucao: 2026-09-22
- Sistema operacional: Microsoft Windows 11 Pro
- Docker Engine: 28.0.4
- Docker Compose: v2.34.0-desktop.1
- Commit de codigo validado: `811b0052a342b6426179a137d18fdf03e85cd064`
- Runner: `./scripts/sec01.ps1 -Action test -EnvFile .env`
- Ambiente: Docker Desktop local, projetos Compose efemeros e valores
  exclusivamente sinteticos

## Componentes

- Vault Community Edition `2.1.1`
- Digest da imagem: `sha256:47f14a6acb98f48d798a07df7c83f23a6e636e1cf724c5f8ff165cb32667a1e2`
- Storage: Raft single-node em volume de teste efemero
- Auth: AppRole com SecretID de uso unico e token service com TTL
- Secret store: KV v2, mount `pdp`
- Control Plane: imagem Python 3.12.8 com Control DB PostgreSQL de teste
- Connection: duas Connections sintéticas em dois domínios sintéticos

## Matriz de validacao

| Criterio | Resultado | Evidencia |
| --- | --- | --- |
| `docker compose config` do Vault e Control Plane | PASS | Configuracao resolvida sem `latest`, com digest fixo e portas/volumes isolados |
| Vault inicia sem dev mode | PASS | Compose usa `server -config` e storage Raft |
| Volume persistente separado dos FND-01/FND-02/FND-04 | PASS | Teste usou volume `pdp-sec01-test-<run>-data`; volumes normais permaneceram presentes e inalterados |
| Init e unseal manual | PASS | Cinco shares, limiar tres; material nao foi impresso nem versionado |
| Recovery fora do Git | PASS | Runner grava fixtures temporarias fora do repositorio; scripts bloqueiam caminhos dentro do repo |
| Recovery protegido por ACL do operador | PASS | Execucao descartavel de `vault.ps1 -Action init` confirmou uma unica regra Allow para o operador atual; falha de ACL remove o arquivo antes de propagar o erro |
| AppRole tecnico com escopo limitado | PASS | Policy ACL permite apenas `read` no caminho da Connection concreta; token service TTL 5m/max 10m; SecretID de uso unico |
| Replay por segundo workload | PASS | O teste tenta autenticar novamente com o mesmo RoleID/SecretID e exige `VaultAuthenticationFailed` |
| SecretID novo por execucao | PASS | Duas execucoes sucessivas usaram o mesmo RoleID e SecretIDs distintos; a credencial anterior foi montada separadamente e rejeitada antes da segunda execucao |
| Credencial inválida | PASS | O teste tenta login com SecretID sintético inválido e exige `VaultAuthenticationFailed` |
| Workload resolve Connection persistida | PASS | `VaultSecretResolver` consulta Control DB e deriva o caminho do registro persistido |
| Referencia arbitraria nao autoriza | PASS | Resolver recebe somente `connection_id`; identidade reconstruida e rejeitada |
| Cross-domain negado | PASS | Segunda Connection/domínio sintético resultou em `PermissionError` |
| Leitura direta de outro caminho negada | PASS | O mesmo token recebeu `VaultAccessDenied` no caminho de outra Connection |
| API nao retorna segredo | PASS | Suite FND-04/FND-06: resposta autorizada sem `secret_ref`/valor e negacao HTTP 403 sanitizada |
| Logs e erros sem segredo | PASS | Cliente e scripts usam mensagens genericas; marcadores sintéticos não apareceram em erros |
| Rotacao sem mudar Connection | PASS | Valor foi alterado no KV2; `secret_ref` da mesma linha permaneceu igual |
| Revogacao | PASS | `revoke-self` seguido de leitura negada pelo Vault |
| Vault sealed | PASS | Login durante `seal` resultou em `VaultSealed` controlado |
| Vault indisponivel | PASS | Login com container parado resultou em `VaultUnavailable` controlado |
| Restart e persistencia | PASS | Container reiniciado, unseal executado e a Connection/valor rotacionado foi lido sem recriacao |
| `clean` protegido contra volume persistente | PASS | Sem confirmacao o comando falha; com confirmacao, um projeto alternativo que resolveria `pdp_vault_data` tambem falha; limpeza descartavel removeu somente volume/rede unicos |
| Backup/restore | PASS | Snapshot Raft restaurado em segunda instancia descartavel isolada; valor sintético conferido |
| Regressao FND-04/FND-06 | PASS | `21 passed, 3 skipped, 1 warning` no ambiente descartavel; os skips sao testes condicionais sem fixtures externas |
| Credenciais reais versionadas | PASS | `.env` ignorado; busca em arquivos rastreados encontrou somente placeholders e nomes de campos |
| Volume PostgreSQL do Polaris preservado | PASS | Snapshot de volume antes/depois sem remoção ou alteração |
| Volumes FND-01 e FND-04 preservados | PASS | `pdp_fnd01_postgres_data`, `pdp_fnd01_rustfs_data` e `pdp-fnd04_control_postgres_data` presentes após o runner |
| Runbook, ADR, licença e limitações documentados | PASS | `docs/runbooks/vault-local.md` e `docs/adr/ADR-021-sec01-local-vault.md` |

## Consumo observado

Medição feita durante a última execução, com `docker stats --no-stream`, no
instante em que o Vault e o Control DB estavam ativos:

| Componente | CPU | Memória |
| --- | ---: | ---: |
| Vault | 12,06% | 28,7 MiB / 8,652 GiB |
| Control DB PostgreSQL | 4,55% | 38,47 MiB / 8,652 GiB |
| Control API/test runner | efêmero; não estava ativo no snapshot final | não aplicável ao snapshot final |
| Spark | NÃO APLICÁVEL | SEC-01 não executa pipeline Spark |

- Tempo total medido do runner SEC-01: 79,8 s.
- Tempo total medido da regressao FND-04/FND-06: 32,9 s.
- Teste isolado de ACL e guard de limpeza: PASS; os recursos descartaveis foram removidos ao final.
- Cold start isolado: não medido separadamente; está incluído no tempo total.
- Tempo do restart/unseal: não medido separadamente; está incluído no tempo total.
- Os números de CPU/memória são uma amostra instantânea, não um peak histórico.

## Testes não executados

- HA/quorum de produção, TLS, KMS/HSM e auditoria operacional de produção.
- Keycloak/OIDC, Kubernetes, cloud, pipeline e integração Spark.
- Carga, concorrência e rotação automática em produção.
- Execucao manual interativa do comando `vault.ps1 -Action issue-credential`; a
  emissão foi exercitada pelo runner SEC-01 contra a API AppRole, com o mesmo
  contrato de SecretID de uso unico, mas o prompt interativo nao foi repetido
  como teste separado.

Esses itens estão fora do SEC-01 local e não foram classificados como PASS.

## Conclusao

Os critérios de aceite do PDP-105 aplicáveis ao laboratório local foram
demonstrados no commit acima. O ciclo de credenciais, a proteção do recovery e
o guard contra limpeza acidental foram revalidados sem remover volumes normais.
O resultado não significa prontidão de produção:
o ambiente continua single-node, HTTP local e com bootstrap/recovery manual.
Não houve merge, alteração de status no Jira ou início de cards PIPE.

Referências:

- [Runbook Vault local](../../../docs/runbooks/vault-local.md)
- [ADR-021](../../../docs/adr/ADR-021-sec01-local-vault.md)
- [Threat model FND-06 atualizado](../../../docs/security/fnd06-identity-secrets-threat-model.md)
