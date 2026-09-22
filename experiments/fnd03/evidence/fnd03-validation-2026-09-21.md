# Evidencia FND-03 - Organizacao do monorepo e convencoes

## Resultado

`FND-03 = PASS` para o escopo documental e de convencoes do PDP-21. O card Jira nao foi movido para `Feito`.

O card manteve o monorepo, nao criou servicos ou repositorios adicionais e nao alterou o runtime dos FND-01/FND-02.

## Ajustes desta revisao

- `docs/adr/0001-repo-inicial.md` passou de `Proposto` para `Adotado para o estagio inicial do projeto`, sem transformar o monorepo em uma obrigacao permanente e preservando os criterios de separacao futura.
- `docs/architecture/monorepo-organization.md` passou a representar explicitamente que o dominio nao depende de casos de uso, adapters ou SDKs externos; casos de uso dependem do dominio e de portas; adapters implementam portas e dependem de contratos internos; apps fazem a composicao.
- Nenhum codigo, pacote, interface, servico ou runtime foi criado.

## Ambiente da validacao

- Repositorio: `O-marqs/projeto-data-platform`
- Branch de trabalho: `feat/fnd03-monorepo-conventions`
- Commit base auditado: `fa3fa29` (main apos merge do PR #2)
- Commit da implementacao documental: `9e384b1`
- Commit efetivamente validado nesta revisao: `c728db1`
- Sistema operacional: Windows no ambiente Codex Desktop
- Data da auditoria: 2026-09-21
- Escopo: revisao estrutural e documental; nenhuma mudanca funcional

## Antes e depois

Antes, o repositorio ja era um monorepo com areas de aplicacao, biblioteca, pipeline, infraestrutura, experimentos, documentacao e fixtures. Havia READMEs de intencao, mas faltavam uma matriz unica de estados, regras explicitas de dependencias, convencoes de contribuicao completas e `CODEOWNERS`.

Depois, foram adicionados:

- `.github/CODEOWNERS`
- `docs/architecture/monorepo-organization.md`
- `experiments/fnd03/evidence/fnd03-validation-2026-09-21.md`

E foram atualizados:

- `README.md`
- `CONTRIBUTING.md`

## Responsabilidades auditadas

| Area | Estado | Resultado |
| --- | --- | --- |
| FND-01/FND-02 | IMPLEMENTADO | Mantidos e referenciados |
| `infra/local/` | IMPLEMENTADO | Mantido sem alteracoes funcionais |
| `experiments/fnd01/` | IMPLEMENTADO | Mantido sem alteracoes funcionais |
| `apps/`, `libs/platform-contracts/`, `pipelines/`, `tests/fixtures/` | ESTRUTURA RESERVADA PARA EVOLUCAO | Responsabilidades documentadas |
| CI/CD, Airflow, Trino, dbt, Kubernetes e Terraform | PLANEJADO | Explicitamente fora do escopo |
| `core`/dominio/casos de uso | INEXISTENTE | Regra documentada; nenhum pacote vazio criado |

## Auditoria de dependencias

Nao existe codigo de `core`, dominio, casos de uso ou portas internas. Portanto, o teste de isolamento de core e `NAO APLICAVEL`, e nao foi inventado um resultado para um componente inexistente.

Os executaveis auditados foram scripts operacionais, `experiments/fnd01/src/run_fnd01.py` com PySpark e `experiments/fnd01/scripts/verify-iceberg-artifacts.py` com biblioteca padrao. Nao foram encontrados imports de app, lib ou pipeline produtivo que criassem uma violacao de fronteira.

## Criterios de aceite

| Criterio | Resultado | Evidencia |
| --- | --- | --- |
| Monorepo preservado | PASS | Nenhum repositorio ou servico novo |
| Responsabilidade por caminho documentada | PASS | `docs/architecture/monorepo-organization.md` |
| Estados implementado/reservado/planejado explicitos | PASS | Matriz de responsabilidades |
| Regra de dependencia e ports/adapters documentada | PASS | Secao de limites de dependencia |
| Ausencia de core tratada sem inventar implementacao | PASS | Auditoria de dependencias |
| README operacional atualizado | PASS | Pre-requisitos, comandos, status e layout |
| CONTRIBUTING operacional atualizado | PASS | Jira, branches, commits, PRs, segredos e evidencia |
| CODEOWNERS criado | PASS | `.github/CODEOWNERS` com `* @O-marqs` |
| Owner do CODEOWNERS valido | PASS | `@O-marqs` e o owner do repositorio; nenhuma equipe foi inventada |
| Links e caminhos locais validos | PASS | Verificacao documental executada |
| Comandos e arquivos publicados existem | PASS | Scripts encontrados e `docker compose config` aprovado com `.env.example` |
| Mudanca funcional FND-01/FND-02 | PASS | Nenhum arquivo de runtime alterado |
| FND-04/FND-05 e novas capabilities preservados fora do escopo | PASS | Nenhum servico, core, CI ou capability nova criada |
| Teste E2E completo do laboratorio | NAO EXECUTADO | Fora do necessario para mudanca apenas documental |
| Teste de isolamento do core | NAO APLICAVEL | Core ainda nao existe |
| CI | NAO EXECUTADO | CI e escopo futuro, fora deste card |

## Verificacoes executadas

- Revisao do diff e da arvore existente.
- Auditoria de executaveis e imports.
- Verificacao de espacos em branco do diff com `git diff --check`.
- Verificacao de links e caminhos locais nos documentos alterados.
- Verificacao de que `.env` nao esta rastreado e que nao ha credenciais reais nos arquivos alterados.
- Verificacao de que a mudanca nao toca Compose, scripts de runtime, codigo PySpark ou configuracoes FND-01/FND-02.
- Verificacao de que os scripts documentados existem e podem ser resolvidos pelo PowerShell.
- `docker compose --env-file .env.example -f infra/local/docker-compose.yml config --quiet` com resultado PASS.
- Verificacao de que `@O-marqs` e um owner valido do repositorio e de que nao ha equipe ficticia no CODEOWNERS.
- `git diff --check` apos os ajustes documentais, com resultado PASS.
- Verificacao dos links relativos nos dois documentos alterados, com resultado PASS.
- Verificacao de que somente documentacao foi alterada nesta revisao, com resultado PASS.

## Verificacoes nao executadas

O Docker Compose completo, smoke test, restart com volumes e homologacao FND-02 nao foram repetidos neste card porque nao houve alteracao funcional nessas areas. A evidencia operacional existente continua em FND-01 e FND-02. Nao ha teste de core para executar enquanto nao existir implementacao de core.

## Riscos e limitacoes reais

- `CODEOWNERS` usa um usuario individual porque nao existe time tecnico configurado no repositorio.
- Areas reservadas ainda nao possuem codigo, testes ou ownership de produto; isso deve ser definido quando cada capability nascer.
- O projeto nao possui CI configurado; a validacao automatica de PR permanece planejada.
- A regra de extracao para multiplos repositorios esta documentada, mas nenhuma extracao e justificada hoje.

## Proximo passo

Submeter este PR para revisao. Nao marcar o Jira como concluido automaticamente e nao avancar FND-04 antes da aprovacao humana.

## Conclusao dos criterios do PDP-21

Todos os criterios aplicaveis do PDP-21 foram demonstrados nesta revisao. Os unicos itens sem execucao funcional sao o E2E Docker completo e o CI; o primeiro permaneceu inalterado e o segundo ainda e planejado. O teste de isolamento do core e `NAO APLICAVEL` porque nao existe core executavel no repositorio.
