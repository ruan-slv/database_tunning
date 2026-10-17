USE tunning;

CREATE TABLE IF NOT EXISTS benchmark_result (
    test_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    categoria VARCHAR(100) NOT NULL,
    versao VARCHAR(10) NOT NULL,
    operacao VARCHAR(255) NOT NULL,
    tempo_ms DECIMAL(18, 3) NOT NULL,
    PRIMARY KEY (test_id)
) ENGINE=InnoDB;
DELETE FROM benchmark_result;

CREATE TABLE IF NOT EXISTS dados_csv_sujo (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    arquivo_origem VARCHAR(255) NOT NULL,
    periodo VARCHAR(100) NOT NULL,
    dados JSON NOT NULL,
    observacoes TEXT NULL,
    PRIMARY KEY (id),
    KEY idx_sujo_origem (arquivo_origem),
    KEY idx_sujo_periodo (periodo),
    KEY idx_sujo_origem_periodo (arquivo_origem, periodo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_dados_csv_sujo_ai;
TRUNCATE TABLE dados_csv_sujo;
INSERT INTO dados_csv_sujo (arquivo_origem, periodo, dados, observacoes)
SELECT arquivo_origem, periodo, dados, observacoes
FROM dados_csv;

CREATE TABLE IF NOT EXISTS auditoria_suja (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    registro_id BIGINT UNSIGNED NOT NULL,
    total_tabela BIGINT UNSIGNED NOT NULL,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_dados_csv_sujo_ai;
DELIMITER $$
CREATE TRIGGER trg_dados_csv_sujo_ai
AFTER INSERT ON dados_csv_sujo
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_suja (registro_id, total_tabela)
    SELECT NEW.id, COUNT(*)
    FROM dados_csv_sujo;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS fn_converter_sujo;
DELIMITER $$
CREATE FUNCTION fn_converter_sujo(p_texto VARCHAR(1000))
RETURNS DECIMAL(18, 6)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_texto VARCHAR(1000);
    SET v_texto = REPLACE(REPLACE(TRIM(p_texto), '%', ''), ',', '.');
    IF v_texto REGEXP '^-?[0-9]+(\\.[0-9]+)?$' THEN
        RETURN CAST(v_texto AS DECIMAL(18, 6));
    END IF;
    RETURN NULL;
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS sp_inserir_sujo;
DELIMITER $$
CREATE PROCEDURE sp_inserir_sujo(
    IN p_arquivo VARCHAR(255),
    IN p_periodo VARCHAR(100),
    IN p_dados JSON,
    IN p_observacoes TEXT
)
BEGIN
    INSERT INTO dados_csv_sujo (arquivo_origem, periodo, dados, observacoes)
    VALUES (p_arquivo, p_periodo, p_dados, p_observacoes);
END$$
DELIMITER ;

SET @benchmark_inicio = NOW(6);
EXPLAIN ANALYZE
SELECT JSON_UNQUOTE(JSON_EXTRACT(d.dados, '$."Sua média de 28 dias"')) AS valor
FROM dados_csv AS d
WHERE LOWER(TRIM(d.arquivo_origem)) =
      LOWER(TRIM('28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'))
  AND LOWER(TRIM(d.periodo)) =
      LOWER(TRIM('31 de mai. a 27 de jun. de 2025'));
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Seleção', 'suja', 'JSON com funções nos filtros', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
EXPLAIN ANALYZE
SELECT v.valor_original AS valor
FROM fonte_csv AS f
INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id
INNER JOIN valor_metrica AS v ON v.observacao_id = o.observacao_id
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
  AND o.periodo = '31 de mai. a 27 de jun. de 2025'
  AND m.nome = 'Sua média de 28 dias';
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Seleção', 'limpa', 'Busca indexada normalizada', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
SELECT COUNT(*) AS total_resultados
FROM (
    SELECT arquivo_origem, periodo
    FROM dados_csv
    WHERE arquivo_origem LIKE '%ratings%'
    UNION
    SELECT arquivo_origem, periodo
    FROM dados_csv
    WHERE observacoes LIKE '%lançamento%'
) AS conjunto_sujo;
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('União de conjuntos', 'suja', 'UNION com busca textual/deduplicação', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
SELECT COUNT(*) AS total_resultados
FROM (
    SELECT f.fonte_id, o.observacao_id
    FROM fonte_csv AS f
    INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id
    WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
    UNION ALL
    SELECT f.fonte_id, o.observacao_id
    FROM fonte_csv AS f
    INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id
    WHERE f.nome = 'Taxa-de-crescimento-do-público_OVERALL_2021_10_18-2026_10_16.csv'
) AS conjunto_limpo;
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('União de conjuntos', 'limpa', 'UNION ALL por fonte', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
SELECT SUM(fn_converter_sujo(JSON_UNQUOTE(JSON_EXTRACT(d.dados, '$."Sua média de 28 dias"'))))
       AS soma_convertida
FROM dados_csv AS d
WHERE d.arquivo_origem = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv';
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Conversão / função', 'suja', 'Converter JSON durante a leitura', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
SELECT SUM(v.valor_numerico) AS soma_armazenada
FROM valor_metrica AS v
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
INNER JOIN observacao AS o ON o.observacao_id = v.observacao_id
INNER JOIN fonte_csv AS f ON f.fonte_id = o.fonte_id
WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
  AND m.nome = 'Sua média de 28 dias';
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Conversão / função', 'limpa', 'Agregação de valor numérico persistido', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
CALL sp_inserir_sujo(
    'benchmark.csv',
    'benchmark-trigger-dirty',
    JSON_OBJECT('metric', '1'),
    'one-row trigger benchmark'
);
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Inserção e trigger', 'suja', 'Procedure e COUNT(*) no trigger', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

INSERT INTO observacao (fonte_id, periodo, observacoes)
SELECT fonte_id, 'benchmark-trigger-clean', 'one-row trigger benchmark'
FROM fonte_csv
WHERE nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
ON DUPLICATE KEY UPDATE observacoes = VALUES(observacoes);

SET @benchmark_inicio = NOW(6);
INSERT INTO valor_metrica (observacao_id, metrica_id, valor_original, valor_numerico)
SELECT o.observacao_id, m.metrica_id, '1', 1
FROM observacao AS o
INNER JOIN fonte_csv AS f ON f.fonte_id = o.fonte_id
INNER JOIN metrica AS m ON m.nome = 'Sua média de 28 dias'
WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
  AND o.periodo = 'benchmark-trigger-clean'
ON DUPLICATE KEY UPDATE valor_original = VALUES(valor_original),
                        valor_numerico = VALUES(valor_numerico);
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Inserção e trigger', 'limpa', 'Inserir valor e auditar nova linha', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
CALL sp_inserir_sujo(
    'benchmark.csv',
    'benchmark-procedure-dirty',
    JSON_OBJECT('metric', '2'),
    'one-row procedure benchmark'
);
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Procedure / carga', 'suja', 'Inserção individual pela procedure', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
CALL sp_sincronizar_dados_csv();
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Procedure / carga', 'limpa', 'Sincronização transacional completa', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
START TRANSACTION;
SELECT COUNT(*) AS total_linhas FROM dados_csv;
COMMIT;
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Transação', 'suja', 'COUNT(*) do estágio', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

SET @benchmark_inicio = NOW(6);
START TRANSACTION READ ONLY;
SELECT (SELECT COUNT(*) FROM observacao) AS total_observacoes,
       (SELECT COUNT(*) FROM valor_metrica) AS total_valores;
COMMIT;
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Transação', 'limpa', 'Contagens normalizadas READ ONLY', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

DROP TABLE IF EXISTS benchmark_dirty_idx;
CREATE TABLE benchmark_dirty_idx (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    arquivo_origem VARCHAR(255) NOT NULL,
    periodo VARCHAR(100) NOT NULL,
    dados JSON NOT NULL,
    observacoes TEXT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO benchmark_dirty_idx (arquivo_origem, periodo, dados, observacoes)
SELECT arquivo_origem, periodo, dados, observacoes
FROM dados_csv;
SET @benchmark_inicio = NOW(6);
ALTER TABLE benchmark_dirty_idx
    ADD KEY idx_bench_sujo_origem (arquivo_origem),
    ADD KEY idx_bench_sujo_periodo (periodo),
    ADD KEY idx_bench_sujo_origem_periodo (arquivo_origem, periodo);
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Criação de índices', 'suja', 'Criar três índices sobrepostos', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

DROP TABLE IF EXISTS benchmark_clean_obs_idx;
CREATE TABLE benchmark_clean_obs_idx (
    observacao_id BIGINT UNSIGNED NOT NULL,
    fonte_id BIGINT UNSIGNED NOT NULL,
    periodo VARCHAR(100) NOT NULL,
    PRIMARY KEY (observacao_id)
) ENGINE=InnoDB;
INSERT INTO benchmark_clean_obs_idx (observacao_id, fonte_id, periodo)
SELECT observacao_id, fonte_id, periodo
FROM observacao;
SET @benchmark_inicio = NOW(6);
ALTER TABLE benchmark_clean_obs_idx
    ADD UNIQUE KEY uq_bench_limpo_fonte_periodo (fonte_id, periodo);

DROP TABLE IF EXISTS benchmark_clean_val_idx;
CREATE TABLE benchmark_clean_val_idx (
    observacao_id BIGINT UNSIGNED NOT NULL,
    metrica_id BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (observacao_id, metrica_id)
) ENGINE=InnoDB;
INSERT INTO benchmark_clean_val_idx (observacao_id, metrica_id)
SELECT observacao_id, metrica_id
FROM valor_metrica;
ALTER TABLE benchmark_clean_val_idx
    ADD KEY idx_bench_limpo_metrica_observacao (metrica_id, observacao_id);
INSERT INTO benchmark_result (categoria, versao, operacao, tempo_ms)
VALUES ('Criação de índices', 'limpa', 'Criar índice único composto e índice de busca', TIMESTAMPDIFF(MICROSECOND, @benchmark_inicio, NOW(6)) / 1000);

DROP TABLE benchmark_dirty_idx, benchmark_clean_obs_idx, benchmark_clean_val_idx;
DELETE v
FROM valor_metrica AS v
INNER JOIN observacao AS o ON o.observacao_id = v.observacao_id
WHERE o.periodo = 'benchmark-trigger-clean';
DELETE FROM observacao WHERE periodo = 'benchmark-trigger-clean';

SELECT categoria, versao, operacao, tempo_ms
FROM benchmark_result
ORDER BY FIELD(categoria, 'Seleção', 'União de conjuntos', 'Conversão / função',
               'Inserção e trigger', 'Procedure / carga', 'Transação', 'Criação de índices'),
         FIELD(versao, 'suja', 'limpa');