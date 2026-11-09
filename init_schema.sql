-- 基础建设第5步: 与 instock/job/init_job.py 第37-42行一致的幂等建表(库 instockdb 已由 compose 预建)
CREATE TABLE IF NOT EXISTS `cn_stock_attention` (
  `datetime` datetime(0) NULL DEFAULT NULL,
  `code` varchar(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`code`) USING BTREE,
  INDEX `INIX_DATETIME`(`datetime`) USING BTREE
) CHARACTER SET = utf8mb4 COLLATE = utf8mb4_general_ci ROW_FORMAT = Dynamic;

SELECT 'TABLES_AFTER_INIT' AS section;
SHOW TABLES;
SELECT COUNT(*) AS cnt_cn_stock_attention FROM `cn_stock_attention`;
