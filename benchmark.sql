USE database_tunning;

-- Consulta custosa: a subconsulta correlacionada pode repetir a agregacao
-- para cada grupo; YEAR(ano) tambem dificulta o uso de indice em ano.
EXPLAIN ANALYZE
SELECT
    grupo.ano,
    grupo.categoria,
    (
        SELECT SUM(detalhe.receita_realizada)
        FROM receitas AS detalhe
        WHERE YEAR(detalhe.ano) = grupo.ano
          AND detalhe.categoria = grupo.categoria
    ) AS receita_realizada_total
FROM (
    SELECT
        YEAR(ano) AS ano,
        categoria
    FROM receitas
    WHERE YEAR(ano) BETWEEN 2024 AND 2026
    GROUP BY YEAR(ano), categoria
) AS grupo
ORDER BY grupo.ano, grupo.categoria;

-- Consulta performatica: filtra por intervalo e agrega os registros uma vez.
-- Com tuning.sql aplicado, pode usar o indice de cobertura proposto.
EXPLAIN ANALYZE
SELECT
    ano,
    categoria,
    SUM(receita_realizada) AS receita_realizada_total
FROM receitas
WHERE ano BETWEEN 2024 AND 2026
GROUP BY ano, categoria
ORDER BY ano, categoria;
