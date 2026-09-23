# Threat model FND-06 / PDP-24

## Escopo

Este documento descreve as fronteiras implementadas para Connection,
autorizacao por dominio e referencias de segredo no laboratorio local. O
resolvedor real do SEC-01 usa Vault local e AppRole, mas este documento nao
declara seguranca de producao, autenticacao humana ou disponibilidade HA.

## Recursos protegidos

- Metadados de `Connection` no Control DB.
- Escopo de dominio associado a cada Connection.
- `secret_ref`, que aponta para um segredo futuro sem conter seu valor.
- Valores de configuracao nao sensiveis retornados pela leitura autorizada.

## Identidades e componentes atuais

- Cliente HTTP: nao e confiavel e nao pode declarar sua propria identidade por
  header.
- FastAPI: aplica a dependencia de identidade, consulta o Control DB e decide
  a autorizacao antes de devolver a Connection.
- Control DB: persiste metadados, constraints e apenas a referencia opaca.
- Testes: injetam `Identity` sintetica por override interno da dependencia.
- Runtime de pipeline e Keycloak: ainda nao existem neste card.
- Vault local: fornece o segredo somente ao resolver autenticado; root token e
  recovery ficam fora do runtime.

## Fronteiras de confianca

Uma requisicao HTTP nao autenticada termina na dependencia
`get_current_identity`, que nega por padrao. A API nao interpreta
`X-User-ID`, `X-Domain-ID`, `X-Role` ou `Authorization` como identidade. Uma
identidade confiavel futura devera chegar por um adapter de autenticacao e
conter subject, dominios e permissoes.

Depois da identidade, o backend avalia a acao `connection:read`, o dominio do
recurso e a permissao. Conhecer o UUID nao substitui o escopo. O retorno contem
somente metadados publicos e nunca inclui `secret_ref` ou valor secreto.

## Ameaças e controles

| Ameaça | Controle implementado |
| --- | --- |
| Cliente forja identidade por header | Headers nao sao lidos; a dependencia padrao retorna HTTP 401. |
| Acesso entre dominios | A identidade precisa conter o `domain_id` da Connection. |
| Acesso direto por UUID conhecido | A mesma verificacao de dominio e permissao e aplicada ao endpoint por ID. |
| Ausencia de permissao | Deny by default; somente `connection:read` ou `connection:admin` leem. |
| Campo generico transporta segredo | A configuracao e uma allowlist plana por tipo (`postgresql` ou `s3`); propriedades desconhecidas, objetos aninhados, listas e tipos escalares incorretos sao rejeitados no modelo e por CHECK constraints do PostgreSQL. |
| Senha em configuracao publica | A allowlist e complementada por rejeicao de userinfo, bearer e padroes de credenciais no modelo e por CHECK constraints existentes. |
| Vazamento em resposta | `secret_ref` nao esta no schema de resposta; erros usam codigos sanitizados. |
| Vazamento em logs | O log registra somente operacao, IDs de recurso/dominio e decisao. |
| `secret_ref` como caminho arbitrario | O formato e restrito a identificador opaco `sref_...`. |
| Resolver recebe ref ou dominio arbitrario | O contrato recebe o ID da Connection, carrega o registro persistido e exige dominio, `connection:resolve`, `workload_id` e autorizacao para o ID concreto. |
| Resolver recebe SecretID de outra Connection | AppRole carrega metadata de dominio, Connection e workload; o resolver compara a identidade em memoria, carrega a Connection persistida e calcula o caminho KV2 a partir dela. |
| Token le outro segredo | Policy ACL tem somente `read` no caminho `pdp/data/connections/{domain_id}/{connection_id}/{secret_ref}`; a tentativa cross-domain e negada pelo Vault e pela camada de autorizacao. |
| Root/unseal chegam ao workload | Somente o operador usa recovery/root durante bootstrap; o workload recebe RoleID/SecretID e token service de TTL curto, com SecretID de usos limitados. |
| Vault sealed ou indisponivel | Cliente transforma HTTP 501/503 e falhas de transporte em erro controlado, sem fallback para secret_ref, sem valor em mensagem e sem retorno HTTP de segredo. |
| Resolver falso selecionado em silencio | O resolver base continua falhando explicitamente; a integracao Vault e opt-in e separada do contrato base. |

## Limites conhecidos

- A allowlist de configuracao cobre somente os tipos e campos necessarios neste
  estagio; nao substitui classificacao de dados, DLP ou um cofre.
- O banco local usa credenciais de laboratorio, sem TLS e sem isolamento de
  usuario de sistema operacional.
- O Vault local e single-node, HTTP sem TLS apenas em loopback, sem HA,
  auditoria operacional ou rate limiting de producao.
- Nao ha autenticacao humana, OIDC ou observabilidade completa.
- A identidade sintetica e confiavel apenas dentro do processo de teste e nao
  pode ser ativada por uma requisicao normal.

## Responsabilidades futuras

**Implementado neste card:** modelo Connection, migrations incrementais,
allowlist publica por tipo, regras de dominio, leitura autorizada, contrato de
`secret_ref` ancorado na Connection persistida, protecao de respostas/logs e
testes de fronteira.

**Implementado SEC-01 / PDP-105:** Vault local persistente, AppRole,
policy por Connection, resolver ancorado no Control DB, TTL/revogacao,
rotacao, sealed/unavailable e runbook de recovery fora do Git.

**Futuro SELF-05 / PDP-39:** Keycloak local, OIDC, autenticacao humana e
integração completa entre identidade real e politica de autorizacao.
