# Benchmark de desempenho e custo de manutenção

## Objetivo e escopo

Este documento compara as duas consultas de agregação apresentadas em
`benchmark.sql` e avalia o efeito do índice criado por `tuning.sql`. A análise
considera desempenho de leitura, custo das operações de escrita/transação e
facilidade de manutenção. Os dados e o ambiente são os descritos em
`README.md`: MySQL 8.0.46, tabela `receitas` com 2.060.000 linhas, das quais
390.000 (18,9%) estão entre 2024 e 2026.

Os registros foram expandidos a partir de 206 linhas de origem, repetindo os
valores de negócio 10.000 vezes. Portanto, o experimento representa o efeito
do volume de linhas, mas não a diversidade ou a distribuição de uma base real.
Os scripts não fornecem tempos medidos nem planos coletados; por isso, este
documento descreve custos esperados e critérios de comparação, sem afirmar
ganhos quantitativos ainda não comprovados.

## Estruturas e consultas comparadas

### Consulta correlacionada: estrutura custosa

A primeira consulta monta os grupos de ano e categoria e calcula a receita de
cada grupo com uma subconsulta correlacionada. Ela também aplica `YEAR()` à
coluna `ano` tanto no filtro quanto na condição de correlação.

Essas escolhas tendem a elevar o trabalho de leitura:

- `YEAR(ano)` transforma a coluna filtrada e pode impedir uma busca eficiente
  por faixa em um índice comum sobre `ano`.
- A subconsulta depende dos valores de cada grupo. Se o plano a executar
  repetidamente, ela relê dados para calcular as somas, em vez de agregar as
  linhas uma só vez.
- A tabela derivada, os agrupamentos e a ordenação podem demandar trabalho
  adicional de memória ou estruturas temporárias, conforme o plano escolhido.

O plano de `EXPLAIN ANALYZE` deve ser consultado para verificar loops e linhas
reais. A forma escrita da consulta sugere repetição, mas não prova por si só
que o otimizador executou a subconsulta uma vez para cada grupo.

### Agregação direta: estrutura performática

A segunda consulta filtra diretamente `ano` pelo intervalo de 2024 a 2026,
agrupa por `ano` e `categoria` e calcula `SUM(receita_realizada)` em uma única
agregação lógica.

Ela evita a subconsulta correlacionada e mantém a coluna do filtro sem função,
o que permite ao otimizador considerar uma busca por faixa. Sem índice, ainda
pode ser necessário percorrer a tabela; com o índice composto adequado, o
plano pode ler as colunas necessárias diretamente do índice. O intervalo
seleciona 18,9% das linhas, então a escolha entre índice e varredura depende
do custo estimado pelo MySQL e deve ser confirmada no plano.

As duas consultas devem produzir as mesmas colunas e totais. A equivalência
dos resultados deve ser validada antes de comparar desempenho.

### Índice de cobertura: benefício de leitura e custo de escrita

`tuning.sql` cria `idx_receitas_ano_categoria_realizada` sobre
`(ano, categoria, receita_realizada)`. A ordem começa pela coluna usada no
filtro por faixa, seguida da categoria de agrupamento. A receita realizada
fica no índice para que a soma possa ser obtida sem buscar as linhas completas
da tabela, se o otimizador escolher esse acesso.

O índice pode reduzir I/O para a consulta direta, mas tem custos permanentes:

- ocupa espaço para até 2.060.000 entradas de índice, além de estruturas e
  páginas de gerenciamento;
- exige trabalho adicional em `INSERT`, `DELETE` e em `UPDATE` de qualquer
  coluna indexada;
- aumenta o tempo e o volume de escrita na carga inicial e em cargas futuras;
- requer espaço e trabalho para ser criado; a criação percorre os dados e
  pode competir por recursos com outras operações.

Há apenas 14 anos e 2 categorias nos dados descritos, e parte substancial dos
valores é repetida pela expansão sintética. Essa baixa diversidade limita a
seletividade do prefixo do índice; portanto, o índice de cobertura não garante
que seja mais barato que uma varredura, especialmente quando a consulta lê
390.000 linhas. O resultado efetivo depende do plano e do armazenamento.

## Custo de transação e carga de dados

`database_tunning.sql` popula a tabela com um único `INSERT ... SELECT` que
gera 2.060.000 linhas a partir das 206 linhas de origem. A operação em lote
evita milhares de comandos `INSERT` individuais e tende a reduzir o custo de
envio e preparação de comandos. Ainda assim, é uma carga grande: o banco deve
escrever todas as linhas e manter os registros de recuperação e consistência
exigidos pela configuração do servidor e pelo mecanismo de armazenamento.
Uma operação longa também pode ocupar recursos por mais tempo e tornar a
recuperação após falha mais demorada.

O script não declara explicitamente uma transação nem o mecanismo da tabela.
Assim, o comportamento exato de atomicidade, bloqueio e recuperação depende da
configuração e do mecanismo padrão do MySQL. Não se deve inferir do script que
a carga está particionada em lotes ou que o rollback terá custo baixo. Em uma
base operacional, avalie o tamanho do lote e a janela de carga conforme os
requisitos de atomicidade, disponibilidade e recuperação; registre essa
decisão e valide-a no ambiente real.

Criar o índice após a carga, como recomenda o README, evita manter sua árvore
durante a inserção de todas as linhas. O custo não desaparece: ele é pago na
construção do índice e em cada escrita subsequente. Para tabelas com alta
frequência de atualização, o benefício de leitura precisa compensar esse custo
contínuo. Se a carga for predominantemente analítica e as escritas forem
raras, a troca tende a ser mais favorável, mas deve ser medida.

As consultas do benchmark são somente leituras e não alteram os dados. Seu
custo transacional é principalmente o de leitura e execução do plano; não é
comparável ao custo de escrita da carga ou da manutenção do índice.
`EXPLAIN ANALYZE` executa a consulta instrumentada, portanto também consome
recursos e seus tempos devem ser coletados em condições consistentes.

## Manutenção e recomendações

| Alternativa | Leitura | Escrita e transação | Manutenção |
|---|---|---|---|
| Subconsulta correlacionada com `YEAR(ano)` | Potencialmente mais leituras, cálculos repetidos e menor aproveitamento de índice; validar loops e linhas no plano. | Sem custo adicional de escrita por si só; a execução consome recursos de leitura. | Mais complexa: lógica de agrupamento e cálculo distribuída entre consulta externa e subconsulta. |
| Agregação direta com `ano BETWEEN` | Evita a subconsulta e permite considerar busca por faixa; sem índice pode varrer a tabela. | Sem custo adicional de escrita por si só; normalmente menos trabalho de leitura que a forma correlacionada, a confirmar por medição. | Mais simples de entender e alterar; filtro, agrupamento e soma estão numa única consulta. |
| Índice `(ano, categoria, receita_realizada)` | Pode cobrir a agregação direta e reduzir leituras da tabela; o otimizador pode não escolhê-lo se a varredura for mais barata. | Aumenta espaço e custo de `INSERT`, `UPDATE` e `DELETE`; a criação consome recursos. | Requer acompanhar uso, tamanho, estatísticas e custo em cargas futuras. Não melhora automaticamente a consulta que aplica `YEAR()` ao filtro. |

Para este caso, a recomendação inicial é manter a agregação direta e tratar o
índice como uma intervenção a comprovar, não como benefício garantido. A
consulta direta também é a mais fácil de manter por expressar a operação
analítica em uma única agregação. Evite adicionar o índice em produção apenas
com base neste experimento sintético.

## Protocolo e registro dos resultados

1. Em ambiente de teste recriável, registre a versão do servidor, mecanismo da
   tabela, CPU, memória e tamanho da tabela.
2. Execute cada consulta duas vezes para aquecer o cache e depois dez vezes,
   primeiro sem o índice. Preserve o plano completo de cada `EXPLAIN ANALYZE`.
3. Calcule a mediana do tempo total da raiz de cada plano. Registre também as
   linhas examinadas, loops da subconsulta e índice/acesso escolhido.
4. Execute `tuning.sql` uma única vez e repita exatamente o mesmo protocolo.
   Não compare execuções feitas sob cargas ou condições de cache diferentes.
5. Compare os resultados agregados para confirmar que continuam idênticos.
   Anote separadamente o tempo de criação do índice e, se o custo de escrita
   for relevante para a aplicação, meça uma carga representativa com e sem
   índice.

| Indicador | Correlacionada, sem índice | Direta, sem índice | Correlacionada, com índice | Direta, com índice |
|---|---:|---:|---:|---:|
| Linhas na tabela | 2.060.000 | 2.060.000 | 2.060.000 | 2.060.000 |
| Mediana do tempo total (10 repetições) | Pendente | Pendente | Pendente | Pendente |
| Linhas examinadas / loops | Pendente | Pendente | Pendente | Pendente |
| Acesso ou índice escolhido pelo plano | Pendente | Pendente | Pendente | Pendente |
| Resultado equivalente | A validar | A validar | A validar | A validar |
| Efeito da consulta sobre dados (leitura/escrita) | Leitura | Leitura | Leitura | Leitura |

## Conclusão

Pelo formato das consultas, a agregação direta tem menor complexidade e evita
o padrão potencialmente repetitivo da subconsulta correlacionada. O índice de
cobertura pode melhorar essa leitura, mas cobra espaço, custo de criação e
manutenção em cada escrita, e sua utilidade é incerta diante da seletividade
limitada do conjunto de dados. A carga inicial em uma única operação reduz a
fragmentação em comandos, mas continua sendo uma transação/carga volumosa cujo
custo de recuperação depende da configuração do banco.

Não há tempos, planos coletados ou medições de escrita preenchidos nos
arquivos do projeto. Portanto, ganhos reais e o saldo entre leitura e escrita
permanecem pendentes de execução do protocolo. Além disso, qualquer conclusão
de produção deve ser validada com dados de maior diversidade e distribuição
representativa, conforme as limitações registradas no README.