USE database_tunning;

-- Cria um indice composto para acelerar a consulta de benchmark que filtra
-- por intervalo de ano, agrupa por categoria e soma a receita realizada.
-- A ordem das colunas prioriza primeiro o filtro por ano e depois a categoria.
-- receita_realizada no indice permite cobrir a soma sem ler todas as colunas
-- da tabela, quando o otimizador escolhe esse plano.
-- O indice ocupa espaco e adiciona custo de manutencao em INSERT/UPDATE/DELETE.
-- Execute uma unica vez, depois de coletar o benchmark sem este indice.
CREATE INDEX idx_receitas_ano_categoria_realizada
    ON receitas (ano, categoria, receita_realizada);
