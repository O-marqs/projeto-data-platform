# ADR-021: Cofre local persistente para o SEC-01

- Status: Aceito para o laboratorio local
- Data: 2026-09-23
- Escopo: SEC-01 / PDP-105

## Contexto

O FND-06 preserva apenas `secret_ref` na Connection e ainda nao tinha uma
fronteira de resolucao de segredos. O primeiro pipeline depende de uma
autenticacao tecnica real, de escopo por Connection e de um armazenamento
persistentemente recuperavel sem colocar root token ou segredo em Git.

## Decisao

Usaremos HashiCorp Vault Community Edition em single-node Raft no laboratorio
local. A imagem e `hashicorp/vault:2.1.1`, fixada pelo digest
`sha256:47f14a6acb98f48d798a07df7c83f23a6e636e1cf724c5f8ff165cb32667a1e2`.
O volume `pdp_vault_data` persiste o estado e o Compose nao usa dev mode.

O operador inicializa e desbloqueia manualmente com cinco shares e limiar de
tres; recovery e root token ficam fora do repositorio. Workloads usam AppRole
com service token de TTL curto e SecretID de uso unico. Cada policy le somente o
caminho KV2 derivado de uma Connection persistida. O resolver consulta o
Control DB para obter dominio, ID e `secret_ref`; uma referencia arbitraria do
chamador nao e autorizacao.

O endpoint local usa HTTP somente em loopback e `host.docker.internal` para a
ponte entre containers e host no Docker Desktop. Essa limitacao nao representa
uma configuracao de producao.

## Consequencias

- FND-06 permanece responsavel por Connection e contrato de identidade;
- SEC-01 habilita um resolver real, rotable e revogavel sem alterar migrations;
- sealed/unavailable produzem falha controlada, sem fallback silencioso;
- single-node, HTTP local, recovery manual e ausencia de HA sao limitacoes
  explicitas;
- pipelines, Keycloak, TLS de producao, Kubernetes e CI continuam fora do
  escopo.

## Licenca e referencias

Vault >= 1.15 usa Business Source License 1.1. A politica adicional permite
uso interno/producao que nao seja uma oferta hospedada concorrente; a equipe
deve validar o caso de distribuicao com o juridico. Referencias: [licenca do
Vault](https://github.com/hashicorp/vault/blob/main/LICENSE), [Docker
oficial](https://hub.docker.com/_/vault) e [AppRole API oficial](https://developer.hashicorp.com/vault/api-docs/auth/approle).
