# Projeto de tuning de banco de dados

## Identificação

- Universidade: Centro Universitário Salesiano.
- Aluno: Ruan Gustavo Soares da Silva.
- Curso: Sistemas de Informação, 6º período noturno.
- SGBD: MySQL. O host local possui o serviço `MySQL80` em execução e o cliente MySQL 8.0.46 instalado.

## Descrição da Entrega:
Estudo independente orientado pelas Unidades de Aprendizagem, resolução de estudos de caso,
atendimento do professor nos fóruns e nos encontros síncronos e desenvolvimento do projeto final.
Ao fim, os alunos deverão entregar um projeto de tunning aplicado a um banco de dados com volume
representativo de dados, comprovando os ganhos obtidos. O trabalho será dividido em 4 partes:


1 - Caracterização do ambiente e da carga de trabalho: os alunos devem descrever o SGBD
utilizado, o modelo de dados, o volume de registros e a carga de trabalho analisada, além de
estabelecer a linha de base de desempenho e os indicadores que serão acompanhados.


2 - Diagnóstico e análise de planos de execução: os alunos devem identificar as consultas mais
custosas, analisar seus planos de execução e apontar as causas dos gargalos observados.


3 - Aplicação das ações de tunning: os alunos devem aplicar ações de otimização em consultas,
índices e projeto físico, justificando cada decisão e registrando os efeitos colaterais previstos,
como custo de escrita e de manutenção.


4 - Comprovação dos resultados e relatório final: os alunos devem repetir as medições após as
intervenções, comparar os resultados com a linha de base, discutir os limites das melhorias
obtidas e entregar o relatório com os scripts utilizados e as recomendações finais.
São sugestões de objetos de estudo: bases públicas de grande volume, bases geradas por ferramentas
de carga sintética, sistemas desenvolvidos em disciplinas anteriores e projetos da fábrica de software.

## Objetivo e fonte dos dados

Este estudo caracteriza e otimiza consultas sobre receitas públicas do Banco Central do Brasil. A fonte é a [consulta de receitas do Portal da Transparência](https://portaldatransparencia.gov.br/receitas/consulta?paginacaoSimples=true&tamanhoPagina=&offset=&direcaoOrdenacao=asc&orgaos=OS25201&colunasSelecionadas=ano%2CorgaoSuperior%2Corgao%2CunidadeGestora%2Ccategoria%2Corigem%2Cespecie%2Cdetalhamento%2CvalorPrevistoAtualizado%2CvalorRealizado%2CpercentualRealizado%2CvalorLancado&ordenarPor=ano&direcao=desc), filtrada para o Banco Central. O arquivo `receitas.csv` foi convertido para os valores de `INSERT` em `database_tunning.sql`.

## 1. Caracterização do ambiente e da carga

O modelo contém uma tabela (`receitas`), com chave primária `id`, ano, hierarquia do órgão, classificação da receita e valores financeiros. Os valores monetários são armazenados em `DECIMAL(18,2)`; o percentual realizado, em `DECIMAL(8,2)`. Essa precisão preserva os centavos e percentuais do CSV.

| Métrica dos dados disponíveis | Valor |
|---|---:|
| Linhas de origem | 206 |
| Registros após expansão sintética x10.000 | 2.060.000 |
| Período | 2013–2026 |
| Anos distintos | 14 |
| Categorias distintas | 2 |
| Soma do orçamento atualizado após expansão | 82.910.529.740.000,00 |
| Soma da receita realizada após expansão | 108.569.868.974.500,00 |
| Registros de 2024 a 2026 após expansão | 390.000 (18,9% da amostra) |

`database_tunning.sql` contém um único `INSERT ... SELECT`: os 206 registros do CSV são declarados uma vez e cruzados com uma sequência de 10.000 valores, gerando exatamente 2.060.000 linhas. Não há necessidade de um script separado de expansão.

**Limitação da expansão:** as 10.000 cópias mantêm os mesmos valores de negócio; somente a chave `id` auto-incrementada é diferente. Portanto, essa expansão avalia o efeito do volume de linhas, mas não aumenta a diversidade nem reproduz a distribuição de uma base real. Não apresentar esses dados sintéticos como 2.060.000 observações independentes. A carga de leitura avaliada é a soma da receita realizada por ano e categoria, limitada a 2024–2026. `benchmark.sql` apresenta duas formas equivalentes de obter o resultado, cada uma acompanhada de `EXPLAIN ANALYZE`.

**Limitação de representatividade:** embora a expansão permita observar o comportamento com 2.060.000 linhas, a origem contém apenas 206 registros de um único órgão. Para conclusões sobre produção, ampliar a base com exportações públicas adicionais ou gerar dados sintéticos com distribuição e cardinalidades justificadas.

## 2. Diagnóstico e plano de execução

**Consulta custosa:** primeiro materializa os grupos em uma tabela derivada e calcula o total de cada grupo com uma subconsulta correlacionada. A subconsulta pode ser executada novamente para cada combinação ano/categoria; além disso, aplica `YEAR()` à coluna `ano`, dificultando uma busca por intervalo em índice e tornando a comparação de cada grupo mais custosa.

**Consulta performática:** filtra diretamente `ano` com `BETWEEN`, agrega as linhas em uma única passagem lógica e não recalcula o total por grupo. O predicado pode usar um índice começando por `ano`; com o índice de cobertura de `tuning.sql`, o MySQL também pode obter a categoria e o valor somado sem consultar as linhas completas da tabela.

As duas consultas devem devolver as mesmas colunas e os mesmos totais. A diferença é deliberadamente didática: a versão correlacionada representa um antipadrão para evidenciar o custo de trabalho repetido; compare os planos reais antes de concluir que o otimizador executou a subconsulta uma vez por grupo. `EXPLAIN ANALYZE` executa a consulta instrumentada e está disponível no MySQL 8.0.18 ou posterior; o cliente instalado é 8.0.46.

## 3. Ação de tuning

`tuning.sql` cria o índice composto e de cobertura `(ano, categoria, receita_realizada)`. A ordem atende ao filtro por intervalo de ano e à agregação por categoria; a última coluna permite obter a soma diretamente pelo índice. O índice só deve ser criado **depois** de coletar a linha de base, e uma única vez.

**Efeitos colaterais:** o índice ocupa armazenamento adicional e aumenta o custo de `INSERT`, `UPDATE` e `DELETE` nas colunas indexadas, além do trabalho de manutenção do índice. Mesmo com 2.060.000 linhas, o otimizador pode preferir uma varredura da tabela; confirmar no plano se o índice foi efetivamente escolhido.

## 4. Comprovação e relatório de resultados

1. Em uma instância de teste MySQL 8.0.18 ou posterior, execute `database_tunning.sql`. Ele recria o banco e insere 2.060.000 linhas em uma única operação; não o execute sobre uma base que não possa ser recriada.
2. Antes do índice de tuning, execute cada consulta de `benchmark.sql` duas vezes para aquecer o cache e depois mais dez vezes. Guarde os planos e o tempo total da raiz de cada `EXPLAIN ANALYZE`.
3. Calcule a mediana de cada conjunto. Execute `tuning.sql` uma vez e repita o protocolo para as duas consultas. O predicado com `YEAR(ano)` pode continuar impedindo o uso do índice mesmo após sua criação.
4. Confirme que os dois resultados agregados são iguais. Compare as medianas, linhas examinadas, loops da subconsulta e índice usado. Registre também a versão do servidor, CPU, memória, tamanho da tabela e quantidade de linhas no teste.

| Indicador | Custosa, sem índice | Performática, sem índice | Custosa, com índice | Performática, com índice |
|---|---:|---:|---:|---:|
| Linhas na tabela | 2.060.000 | 2.060.000 | 2.060.000 | 2.060.000 |
| Mediana do tempo total (10 repetições) | Pendente | Pendente | Pendente | Pendente |
| Linhas examinadas / loops | Pendente | Pendente | Pendente | Pendente |
| Índice usado pelo plano | Pendente | Pendente | Pendente | Pendente |
| Resultado equivalente | A validar | A validar | A validar | A validar |

**Conclusão provisória:** as formas equivalentes de consulta e o protocolo estão preparados, mas não há evidência para afirmar que uma seja mais rápida até coletar os tempos e planos. A replicação testa volume, não diversidade; resultados devem ser interpretados como um experimento sintético e complementados com uma amostra mais representativa.
