USE tunning;

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
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS auditoria_suja (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    registro_id BIGINT UNSIGNED NOT NULL,
    total_tabela BIGINT UNSIGNED NOT NULL,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

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

SELECT * 
FROM dados_csv; 

SELECT arquivo_origem, periodo, dados
FROM dados_csv
WHERE arquivo_origem LIKE '%ratings%' 
UNION
SELECT arquivo_origem, periodo, dados
FROM dados_csv
WHERE observacoes LIKE '%lançamento%'; 

SELECT id, arquivo_origem, periodo,
       fn_converter_sujo(JSON_UNQUOTE(JSON_EXTRACT(dados, '$."Sua média de 28 dias"'))) AS valor_convertido
FROM dados_csv
WHERE LOWER(TRIM(arquivo_origem)) LIKE '%brasil%' 
   OR observacoes LIKE '%falha%'; 

SELECT d.id, d.periodo,
       (SELECT COUNT(*)
        FROM dados_csv x
        WHERE x.arquivo_origem = d.arquivo_origem) AS linhas_da_origem
FROM dados_csv d
ORDER BY LOWER(d.periodo); 

SELECT a.id, b.id
FROM dados_csv a
CROSS JOIN dados_csv b
WHERE a.id <> b.id
ORDER BY a.id, b.id
LIMIT 100; 

START TRANSACTION; 
SELECT COUNT(*) AS total_linhas FROM dados_csv; 
COMMIT;