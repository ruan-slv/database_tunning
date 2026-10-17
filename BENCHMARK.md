# Benchmark de consultas — MySQL

Esta entrega de produto 1 e 2 tem como objetivo realizar comparações entre estruturas SGBD's com intuito de verificar o nível de custo entre cada consulta ou query realizada no presente trabalho. Também foi verificado/abordado outras métricas como escalabilidade e manutenção. Pois foi visto que nem toda query "Limpa" era mais rápida nos testes de benchmark. Siga abaixo o quadro de avaliação e as ferramentas utilizadas:

## Caracteristicas da entrega de produto 1 e 2
- Fonte de dados: Arquivos .csv exportados atráves do google play console do meu aplicativo publicado na play store ([Bíblia & Harpa - sem anúncios](https://play.google.com/store/apps/details?id=com.bibleAplication.app)).
- Banco de dados: Mysql
- Outros: Docker e docker-compose para levantar o container do mysql

## Máquina Utilizada
- Modelo: Acer Aspire A515-54
- Processador: Intel i5-10210U CPU @ 1.60GHz (2.11 GHz)
- Ram: 20GB ram DDR4
- Placa Gráfica: UHD Graphics (128MB)
- Armazenamento: SSD NVME 500GB
- Sistema Operacional: Windows 11 Home

## Requisitos
O primeiro passo adotado após levantar um container docker foi criar a database `tunning` e carregar os dados do arquivo `script.sql`, onde o serviço fica rodando na porta 3307 no localhost e tendo o volume `mysql_data` para preservar os dados durante as reinicializações.

## Preparação do modelo limpo

Execute a transformação uma vez depois que o serviço estiver funcionando:

```powershell
docker compose exec -T db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" < /work/limpo.sql'
```

O script cria as tabelas normalizadas, sincroniza os dados e instala a auditoria, podendo ser executado novamente para sincronização da tabela de estágio.

## Execução e Preparação

Processo de execução do conjunto de consultas:

```powershell
docker compose exec -T db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" --verbose -t < /work/benchmark.sql'
```

O benchmark prepara uma cópia de `dados_csv` para os testes sujos, executa os
testes das categorias abaixo e remove as tabelas temporárias. A tabela
`dados_csv_sujo` e o conteúdo delas são próprios do benchmark; a preparação apaga
e recria somente os dados dessa tabela. `--verbose` faz o cliente MySQL mostrar
o tempo decorrido em cada instrução (`Query OK` / `rows in set`).

Para as consultas `EXPLAIN ANALYZE`, compare os blocos `SUJO` e `LIMPO`, em especial:

- `actual time`: duração do processamento do servidor para cada etapa;
- `rows`: quantidade real de linhas examinadas/retornadas;
- `loops`: número de vezes que uma etapa do plano foi executada.

Para uma comparação mais justa, foi executado o benchmark algumas vezes sem reiniciar
o container e comparado as execuções com cache aquecido. Foi registrado a máquina, a versão
do Docker, o total de linhas e os tempo observado em cada operação.

## Tempos por categorias

| Categoria / operação | Query suja (`sujo.sql`) | Tempo sujo | Query limpa (`limpo.sql`) | Tempo limpo |
|---|---|---:|---|---:|
| Seleção da média de avaliações | JSON com funções nos filtros; table scan | 11,945–23,934 ms | Busca indexada no modelo normalizado | 0,594–2,468 ms |
| União de conjuntos | `UNION` com busca textual e eliminação de duplicatas | 13,416–30,803 ms | `UNION ALL` com filtros por fonte | 0,721–2,370 ms |
| Conversão de métrica / função | Conversão do JSON durante a leitura | 5,026–11,329 ms | Conversão na carga; valor numérico persistido para agregação | 0,456–1,406 ms |
| Inserção e trigger | Procedure insere uma linha; trigger conta a tabela inteira | 9,679–18,590 ms | Inserção de um valor; trigger audita somente a nova linha | 4,165–6,380 ms |
| Procedure / carga de dados | Procedure insere uma linha na tabela suja | 8,419–21,580 ms | Procedure sincroniza a tabela de estágio em transação | 1.644,138–4.010,265 ms |
| Transação | `COUNT(*)` do estágio em transação de leitura | 1,681–3,701 ms | Contagens normalizadas em transação `READ ONLY` | 5,703–11,858 ms |
| Criação de índices | Criação de três índices sobrepostos | 357,829–505,026 ms | Índice único composto e índice de busca em duas tabelas | 608,756–918,808 ms |

**Condições da medição:** MySql em Docker, foi manipuladas 9.654 linhas na tabela
de estágio e duas execuções de `benchmark/benchmark.sql`. A tabela mostra a
faixa mínimo–máximo observada e não uma média; cada execução sobrescreve a tabela
`benchmark_result` com o seus próprios tempos medidos no servidor.

Algumas operações não fazem exatamente o mesmo trabalho: a procedure suja
insere uma linha, enquanto a limpa sincroniza todo o estágio; a transação limpa
conta observações e valores; o teste de índices constrói índices em tabelas
com volumes/formatos diferentes. Portanto, os tempos servem como diagnóstico do
cenário demonstrado, não como comparação controlada de custo equivalente. O
teste de inserção mede também o custo de manter os índices presentes. Os valores
variam conforme CPU, memória, cache e carga concorrente.