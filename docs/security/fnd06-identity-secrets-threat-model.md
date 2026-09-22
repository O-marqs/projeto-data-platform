# Threat model FND-06 / PDP-24

## Escopo

Este documento descreve as fronteiras implementadas para Connection,
autorizacao por dominio e referencias de segredo no laboratorio local. Ele nao
declara seguranca de producao, autenticacao humana ou resolucao real de
segredos.

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
- Runtime de pipeline, Keycloak e Vault: ainda nao existem neste card.

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
| Senha em configuracao publica | Chaves e padroes de valores sensiveis sao rejeitados no modelo. |
| Vazamento em resposta | `secret_ref` nao esta no schema de resposta; erros usam codigos sanitizados. |
| Vazamento em logs | O log registra somente operacao, IDs de recurso/dominio e decisao. |
| `secret_ref` como caminho arbitrario | O formato e restrito a identificador opaco `sref_...`. |
| Resolver falso selecionado em silencio | Nao existe resolvedor configurado; o contrato falha explicitamente. |

## Limites conhecidos

- A validacao de configuracao e uma barreira de contrato para o conjunto de
  padroes conhecidos; nao substitui classificacao de dados ou DLP.
- O banco local usa credenciais de laboratorio, sem TLS e sem isolamento de
  usuario de sistema operacional.
- Nao ha autenticacao real, rotacao, auditoria, rate limiting ou observabilidade
  completa.
- A identidade sintetica e confiavel apenas dentro do processo de teste e nao
  pode ser ativada por uma requisicao normal.

## Responsabilidades futuras

**Implementado neste card:** modelo Connection, migration incremental, regras
de dominio, leitura autorizada, contrato de `secret_ref`, protecao basica de
respostas/logs e testes de fronteira.

**Futuro SEC-01 / PDP-105:** Vault local, autenticacao tecnica do runtime,
resolucao real e entrega controlada do valor secreto ao workload autorizado.

**Futuro SELF-05 / PDP-39:** Keycloak local, OIDC, autenticacao humana e
integração completa entre identidade real e politica de autorizacao.
