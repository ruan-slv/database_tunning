USE tunning; 

CREATE TABLE IF NOT EXISTS fonte_csv (
    fonte_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, 
    nome VARCHAR(255) NOT NULL, 
    PRIMARY KEY (fonte_id), 
    UNIQUE KEY uq_fonte_csv_nome (nome) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci; 

CREATE TABLE IF NOT EXISTS observacao (
    observacao_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, 
    fonte_id BIGINT UNSIGNED NOT NULL, 
    periodo VARCHAR(100) NOT NULL, 
    observacoes TEXT NULL, 
    PRIMARY KEY (observacao_id), 
    UNIQUE KEY uq_observacao_fonte_periodo (fonte_id, periodo), 
    CONSTRAINT fk_observacao_fonte FOREIGN KEY (fonte_id) REFERENCES fonte_csv (fonte_id) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci; 

CREATE TABLE IF NOT EXISTS metrica (
    metrica_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, 
    nome VARCHAR(500) NOT NULL, 
    PRIMARY KEY (metrica_id), 
    UNIQUE KEY uq_metrica_nome (nome) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci; 

CREATE TABLE IF NOT EXISTS valor_metrica (
    observacao_id BIGINT UNSIGNED NOT NULL, 
    metrica_id BIGINT UNSIGNED NOT NULL, 
    valor_original VARCHAR(1000) NOT NULL, 
    valor_numerico DECIMAL(18, 6) NULL, 
    PRIMARY KEY (observacao_id, metrica_id), 
    KEY idx_valor_metrica_busca (metrica_id, observacao_id), 
    CONSTRAINT fk_valor_observacao FOREIGN KEY (observacao_id) REFERENCES observacao (observacao_id), 
    CONSTRAINT fk_valor_metrica FOREIGN KEY (metrica_id) REFERENCES metrica (metrica_id) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci; 

CREATE TABLE IF NOT EXISTS auditoria_valor_metrica (
    auditoria_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, 
    observacao_id BIGINT UNSIGNED NOT NULL, 
    metrica_id BIGINT UNSIGNED NOT NULL, 
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, 
    PRIMARY KEY (auditoria_id), 
    KEY idx_auditoria_criado_em (criado_em) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci; 

DROP FUNCTION IF EXISTS fn_valor_decimal; 
DELIMITER $$ 
CREATE FUNCTION fn_valor_decimal(p_texto VARCHAR(1000))
RETURNS DECIMAL(18, 6)
DETERMINISTIC
NO SQL
BEGIN    
    DECLARE v_texto VARCHAR(1000);
    IF p_texto IS NULL OR TRIM(p_texto) IN ('', '-') THEN
        RETURN NULL;
    END IF;
    
    SET v_texto = REPLACE(REPLACE(TRIM(p_texto), '%', ''), ',', '.');
    
    IF v_texto REGEXP '^-?[0-9]+(\\.[0-9]+)?$' THEN
        RETURN CAST(v_texto AS DECIMAL(18, 6));
    END IF;
    
    RETURN NULL;
END$$
DELIMITER ; 

DROP PROCEDURE IF EXISTS sp_sincronizar_dados_csv; 
DELIMITER $$ 
CREATE PROCEDURE sp_sincronizar_dados_csv()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT IGNORE INTO fonte_csv (nome)
    SELECT DISTINCT arquivo_origem
    FROM dados_csv;
    
    INSERT INTO observacao (fonte_id, periodo, observacoes)
    SELECT f.fonte_id, d.periodo, d.observacoes
    FROM dados_csv AS d
    INNER JOIN fonte_csv AS f ON f.nome = d.arquivo_origem
    WHERE 1 = 1 
    ON DUPLICATE KEY UPDATE observacoes = VALUES(observacoes);
    
    INSERT IGNORE INTO metrica (nome)
    SELECT DISTINCT j.chave
    FROM dados_csv AS d
    CROSS JOIN JSON_TABLE(
        JSON_KEYS(d.dados),
        '$[*]' COLUMNS (chave VARCHAR(500) PATH '$')
    ) AS j;

    INSERT INTO valor_metrica (observacao_id, metrica_id, valor_original, valor_numerico)
    SELECT o.observacao_id,
           m.metrica_id,
           JSON_UNQUOTE(JSON_EXTRACT(d.dados, CONCAT('$.', JSON_QUOTE(j.chave)))),
           fn_valor_decimal(JSON_UNQUOTE(JSON_EXTRACT(d.dados, CONCAT('$.', JSON_QUOTE(j.chave)))))
    FROM dados_csv AS d
    INNER JOIN fonte_csv AS f ON f.nome = d.arquivo_origem
    INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id AND o.periodo = d.periodo
    CROSS JOIN JSON_TABLE(
        JSON_KEYS(d.dados),
        '$[*]' COLUMNS (chave VARCHAR(500) PATH '$')
    ) AS j
    INNER JOIN metrica AS m ON m.nome = j.chave
    WHERE 1 = 1 
    ON DUPLICATE KEY UPDATE
        valor_original = VALUES(valor_original),
        valor_numerico = VALUES(valor_numerico);
    COMMIT;
END$$
DELIMITER ; 

CALL sp_sincronizar_dados_csv(); 

DROP TRIGGER IF EXISTS trg_valor_metrica_ai; 
DELIMITER $$ 
CREATE TRIGGER trg_valor_metrica_ai
AFTER INSERT ON valor_metrica
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_valor_metrica (observacao_id, metrica_id)
    VALUES (NEW.observacao_id, NEW.metrica_id);
END$$
DELIMITER ; 

SELECT f.nome AS arquivo,
       o.periodo,
       m.nome AS metrica,
       v.valor_numerico
FROM fonte_csv AS f
INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id
INNER JOIN valor_metrica AS v ON v.observacao_id = o.observacao_id
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
  AND o.periodo = '31 de mai. a 27 de jun. de 2025'; 

SELECT f.nome AS arquivo, o.periodo, m.nome AS metrica, v.valor_numerico
FROM fonte_csv AS f
INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id
INNER JOIN valor_metrica AS v ON v.observacao_id = o.observacao_id
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
UNION ALL
SELECT f.nome AS arquivo, o.periodo, m.nome AS metrica, v.valor_numerico
FROM fonte_csv AS f
INNER JOIN observacao AS o ON o.fonte_id = f.fonte_id
INNER JOIN valor_metrica AS v ON v.observacao_id = o.observacao_id
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
WHERE f.nome = 'Taxa-de-crescimento-do-público_OVERALL_2021_10_18-2026_10_16.csv'; 

SELECT m.nome AS metrica,
       fn_valor_decimal(v.valor_original) AS valor_convertido
FROM valor_metrica AS v
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
INNER JOIN observacao AS o ON o.observacao_id = v.observacao_id
INNER JOIN fonte_csv AS f ON f.fonte_id = o.fonte_id
WHERE f.nome = '28-Day Average ratings _ 2025-05-31 - 2026-09-19.csv'
  AND o.periodo = '31 de mai. a 27 de jun. de 2025'; 

SELECT AVG(v.valor_numerico) AS media
FROM valor_metrica AS v
INNER JOIN metrica AS m ON m.metrica_id = v.metrica_id
WHERE m.nome = 'Sua média de 28 dias'
  AND v.valor_numerico IS NOT NULL; 

START TRANSACTION READ ONLY; 
SELECT COUNT(*) AS total_observacoes FROM observacao; 
SELECT COUNT(*) AS total_valores FROM valor_metrica; 
COMMIT;