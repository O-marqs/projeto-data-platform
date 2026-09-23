# Runbook Vault Local

## Escopo

Este runbook opera o Vault Community Edition usado pelo SEC-01/PDP-105 no
laboratorio local. Ele nao configura Keycloak, Kubernetes, pipelines ou uma
topologia de producao.

| Item | Valor |
| --- | --- |
| Imagem | `hashicorp/vault:2.1.1` |
| Digest | `sha256:47f14a6acb98f48d798a07df7c83f23a6e636e1cf724c5f8ff165cb32667a1e2` |
| Persistencia | Raft single-node em `pdp_vault_data` |
| Projeto Compose | `pdp-vault` |
| Rede | `pdp_vault_network` |
| Endpoint do host | `http://127.0.0.1:18200` |
| Endpoint no Control Plane | `http://host.docker.internal:18200` |
| Auth de workload | AppRole em `approle/` |
| Segredo | KV v2 em `pdp/` |

O digest e a versao sao fixos no Compose e no `.env.example`; nao use
`latest`. A imagem e distribuida sob Business Source License 1.1 desde o
Vault 1.15, com a concessao adicional publicada pelo projeto para uso interno
e de producao que nao seja uma oferta hospedada concorrente. Consulte a
[licenca oficial do Vault](https://github.com/hashicorp/vault/blob/main/LICENSE)
e as [notas oficiais da imagem Docker](https://hub.docker.com/_/vault).
Valide a politica juridica da organizacao antes de redistribuir o produto.

## Bootstrap manual

1. Crie o `.env` local a partir do exemplo e confirme que a porta `18200` esta
   livre.

   ```powershell
   Copy-Item .env.example .env
   ./scripts/vault.ps1 -Action up
   ./scripts/vault.ps1 -Action status
   ```

2. Inicialize uma unica vez, apontando para um caminho fora do repositorio.
   O arquivo contem material de recovery e root token; trate-o como segredo
   operacional e nao o envie para Git, chat, imagem ou log.

   ```powershell
   ./scripts/vault.ps1 -Action init -RecoveryFile C:\secure\pdp-vault-recovery.json
   ```

3. Desbloqueie com tres das cinco chaves gravadas no arquivo externo.

   ```powershell
   ./scripts/vault.ps1 -Action unseal -RecoveryFile C:\secure\pdp-vault-recovery.json
   ./scripts/vault.ps1 -Action status
   ```

   O script espera o estado ativo antes de concluir. Perder o material de
   recovery torna os dados persistidos irrecuperaveis neste laboratorio.

## Registrar uma Connection

O operador usa temporariamente o root token ou um token administrativo
equivalente somente para criar o mount, policy, AppRole e valor KV de uma
Connection concreta. O script solicita o token e o valor em `SecureString` e
nao os imprime.

```powershell
./scripts/vault.ps1 -Action configure `
  -DomainId <domain-uuid> `
  -ConnectionId <connection-uuid> `
  -WorkloadId <workload-id> `
  -SecretRef sref_<opaque-id> `
  -CredentialFile C:\secure\pdp-workload.json
```

O segredo fica em `pdp/data/connections/{domain_id}/{connection_id}/{secret_ref}`.
A policy permite apenas `read` nesse caminho. O arquivo de credencial externo
conta apenas com RoleID e SecretID; nunca contém o root token ou as chaves de
unseal. O runtime deve receber esse arquivo por mecanismo de segredo do
ambiente e não deve gravar seu conteúdo em logs.

## Fronteira do runtime

`VaultSecretResolver` recebe um `connection_id`, uma identidade de workload
produzida pelo login AppRole e uma sessao do Control DB. Ele carrega a
Connection persistida, valida dominio, workload e ID concreto, calcula o
caminho a partir de `secret_ref` e somente então lê KV2. Um `secret_ref`
fornecido isoladamente, um caminho arbitrario ou uma identidade reconstruida
nao autoriza leitura. A API HTTP continua retornando somente configuracao
publica; o valor nunca aparece em resposta, erro ou log.

Workload tokens sao `service`, com TTL de cinco minutos, max TTL de dez minutos
e SecretID de uso unico. O workload nao recebe root token, chave de unseal
ou permissao administrativa.

## Rotacao e revogacao

Para rotacionar, escreva um novo valor no mesmo caminho e preserve o
`secret_ref` da Connection. Novos tokens devem ler o valor novo; nao altere a
linha da Connection para trocar o material secreto. Revogue um token no
processo com `revoke-self` ou, em incidente, por accessor com um token
administrativo temporario. A evidencia do SEC-01 executa ambas as verificacoes.

## Restart, backup e restore

`down` preserva `pdp_vault_data`; `clean` e destrutivo e deve ser usado somente
quando o laboratorio puder perder o cofre.

```powershell
./scripts/vault.ps1 -Action down
./scripts/vault.ps1 -Action up
./scripts/vault.ps1 -Action unseal -RecoveryFile C:\secure\pdp-vault-recovery.json
```

Para um ensaio de backup/restore, use um projeto e volume descartaveis, nunca
`pdp-vault` nem os volumes de FND-01/FND-02/FND-04. Com Vault ativo, o operador
pode criar um snapshot Raft usando o CLI dentro do container, copiar o arquivo
para um diretorio externo e restaurar em uma segunda instancia single-node
descartavel. Depois do restore, unseal e leia uma Connection sintetica para
confirmar o valor. Apague o segundo projeto e o snapshot ao terminar. O
snapshot contem segredos e deve permanecer fora do Git.

## Falhas e limites

- sealed ou indisponivel: o resolver falha com erro controlado; nao ha fallback
  para `secret_ref` nem para o banco;
- HTTP sem TLS: aceitavel somente para a porta loopback deste laboratorio;
- single-node: nao ha HA, quorum de producao ou replicacao;
- `host.docker.internal`: depende de Docker Desktop/host gateway; em Linux
  sem esse recurso, substitua `VAULT_ADDR` por um endpoint acessivel na rede
  local, sem tornar o endpoint publico;
- recovery e backup: responsabilidade do operador, sempre fora do Git.

O fluxo completo e reproduzivel com:

```powershell
./scripts/sec01.ps1 -Action test
```

Esse comando cria projeto, banco, rede, portas e volumes descartaveis, executa
os testes de escopo/rotacao/revogacao/restart/falha e os remove ao final. Ele
nao executa `down --volumes` em nenhum ambiente persistente do projeto.
