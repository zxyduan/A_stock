-- =============================================================================
-- gap_extra_review.sql  #9 行业字典 / #2 估值时序增量 / #10 双价格口径【只读评审草案】
-- 纪律（重要）：
--   * 本文件【可执行语句仅 SELECT / SHOW 只读】；所有 CREATE/ALTER 均以 "--" 注释，禁止整段 source 建表/改表；
--   * #2 估值不做历史回填（免费长序列端点不可得，已在前期只读探针证伪），只设计“每日截面增量累积”；
--   * #10 涉及给既有快照表 ALTER 加列，属于改线上旧表结构，默认不执行，需另行授权；
--   * #9 字典表为新表，默认只出结构草案与只读对照，不建表、不灌库。
-- 目标库: instockdb；执行方式: 只复制其中不带 -- 的 SELECT/SHOW 到 mariadb 只读会话运行。
-- =============================================================================


-- =============================================================================
-- #9 行业分类口径不统一：selection.industry 与资金榜行业名无法直接 JOIN
--   现象（data-inventory / 前期分析）：selection 用“饮料/畜牧业/非银行金融/零售”，
--   资金表用“白酒Ⅲ/生猪养殖/保险Ⅱ/旅游零售Ⅱ”，需人工映射。
--   默认方案：建 dim_industry 字典 + 在分析层映射；本批不建表。
-- -----------------------------------------------------------------------------
-- 9.0 只读核对列名（2026-11-10 实测：selection.industry；资金表行业名为 name, PK(date,name),无 industry 列）
SHOW COLUMNS FROM cn_stock_selection LIKE 'industry%';
SHOW COLUMNS FROM cn_stock_fund_flow_industry;

-- 9.1 selection 侧行业值分布（只读；最新截面）
SELECT industry, COUNT(*) AS n
FROM cn_stock_selection
WHERE date = (SELECT MAX(date) FROM cn_stock_selection)
GROUP BY industry
ORDER BY n DESC
LIMIT 40;

-- 9.1b 资金表侧行业名样本（只读；行业名列=name，供与 selection.industry 建别名映射）
SELECT DISTINCT name
FROM cn_stock_fund_flow_industry
WHERE date = (SELECT MAX(date) FROM cn_stock_fund_flow_industry)
ORDER BY name
LIMIT 80;

-- 9.2 候选字典表结构（【注释，不执行】；等两表行业值样本采集齐再定 aliases 映射规则）
-- CREATE TABLE IF NOT EXISTS `dim_industry` (
--   `industry_code` varchar(24) NOT NULL COMMENT '标准化行业编码(自建)',
--   `std_name`      varchar(32) NOT NULL COMMENT '标准行业名(level1/level2归一)',
--   `level1`         varchar(32) DEFAULT NULL,
--   `level2`         varchar(32) DEFAULT NULL,
--   `sel_name`       varchar(32) DEFAULT NULL COMMENT 'selection.industry 原始别名',
--   `fund_name`      varchar(32) DEFAULT NULL COMMENT '资金表行业别名 <- cn_stock_fund_flow_industry.name',
--   `source`         varchar(24) DEFAULT 'manual_map',
--   PRIMARY KEY (`industry_code`),
--   KEY `idx_sel` (`sel_name`),
--   KEY `idx_fund` (`fund_name`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='行业名归一字典(selection<->资金表);人工映射,不替代证监会分类';


-- =============================================================================
-- 9.3 行业名基数与字面交集（只读；2026-11-10 实测 sel=103 fund=496 精确同名交集=39）
SELECT (SELECT COUNT(DISTINCT industry) FROM cn_stock_selection) AS sel_distinct,
       (SELECT COUNT(DISTINCT name) FROM cn_stock_fund_flow_industry) AS fund_distinct;

SELECT COUNT(*) AS exact_name_overlap
FROM (SELECT DISTINCT industry FROM cn_stock_selection) a
JOIN (SELECT DISTINCT name FROM cn_stock_fund_flow_industry) b ON a.industry = b.name;

-- 9.4 客观后缀清洗证据（仅去罗马数字 Ⅱ/Ⅲ，不做人工归并；只读；不建表）
SELECT COUNT(DISTINCT name) AS fund_raw_distinct,
       COUNT(DISTINCT REPLACE(REPLACE(name, 'Ⅱ', ''), 'Ⅲ', '')) AS fund_suffix_cleaned_distinct
FROM cn_stock_fund_flow_industry;

SELECT COUNT(*) AS cleaned_overlap_selection
FROM (SELECT DISTINCT industry FROM cn_stock_selection) a
JOIN (SELECT DISTINCT REPLACE(REPLACE(name, 'Ⅱ', ''), 'Ⅲ', '') AS cn
      FROM cn_stock_fund_flow_industry) b ON a.industry = b.cn;

-- 9.5 资金表细分名中未被 selection 字面覆盖的样本（人工映射候选清单，只读；Top 40）
SELECT DISTINCT f.name
FROM cn_stock_fund_flow_industry f
LEFT JOIN (SELECT DISTINCT industry FROM cn_stock_selection) s ON s.industry = f.name
WHERE s.industry IS NULL
ORDER BY f.name
LIMIT 40;

-- =============================================================================
-- #2 估值历史序列与分位（PE/PB/PS 时序）
--   结论：免费历史长序列端点不可得（前期探针证伪）；默认只做“截面每日增量累积”，
--   不承诺回填多年历史；由收盘作业把当日 selection 最新截面的 pe9/pbnewmrq/ps9 落时序表。
-- -----------------------------------------------------------------------------
-- 2.0 现有 selection 截面覆盖度（只读）；2026-11-10 实测仅近几个交易日截面
--      (2026-11-06~09, 8668行/4527只)，无多年历史 -> #2 只能每日增量累积，不可从此表回填长序列。
SELECT MIN(date), MAX(date), COUNT(*) AS rows_, COUNT(DISTINCT code) AS codes
FROM cn_stock_selection;

-- 2.1 候选时序表结构（【注释，不执行】；PK(code,date) 幂等，每日 upsert/ignore 当日一行）
-- CREATE TABLE IF NOT EXISTS `cn_stock_valuation_daily` (
--   `code` varchar(10) NOT NULL,
--   `date` date NOT NULL,
--   `pe9`  decimal(18,4) DEFAULT NULL COMMENT '取自 selection.pe9(同日截面,不复权口径)',
--   `pbnewmrq` decimal(18,4) DEFAULT NULL COMMENT 'selection.pbnewmrq',
--   `ps9`  decimal(18,4) DEFAULT NULL COMMENT 'selection.ps9',
--   `source` varchar(24) DEFAULT 'FROM_SELECTION_SNAPSHOT',
--   PRIMARY KEY (`code`,`date`),
--   KEY `idx_date` (`date`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='估值截面时序(仅每日增量,不回填历史;分位由分析层滚动计算)';
-- 落地前置：不改外部爬取；在收盘作业稳定后追加一步“当日 SELECT 截面 -> 该表 IGNORE/UPSERT”，
--          历史分位随时间自然累积；pe/pb 缺失、负值、亏损股需在分析层显式剔除。


-- =============================================================================
-- #10 两套价格口径并存（快照 new_price vs qfq 日线收盘）
--   默认纪律：位置/趋势/回撤一律用 cn_stock_daily_kline(adjust='qfq')；
--   快照 new_price 为“当日不复权现价截面”，二者口径不同、不可直接相减当涨跌。
--   候选改造为给快照表加 price_raw/price_qfq 标注列（【ALTER 注释，不执行】，需另行授权）。
-- -----------------------------------------------------------------------------
-- 10.0 只读抽样：对比最新 selection.new_price 与同日 qfq 收盘（口径差异确认；不写库）
SELECT s.date, s.code, s.name, s.new_price,
       k.close AS qfq_close,
       ROUND((s.new_price - k.close) / NULLIF(k.close, 0) * 100, 2) AS diff_pct
FROM cn_stock_selection s
LEFT JOIN cn_stock_daily_kline k
  ON k.code = s.code AND k.date = s.date AND k.adjust = 'qfq'
WHERE s.code IN ('300308','600519','000001')
  AND s.date = (SELECT MAX(date) FROM cn_stock_selection)
ORDER BY s.code;

-- 10.1 候选口径标注（【注释，不执行】；改既有快照表结构，默认禁止）
-- ALTER TABLE cn_stock_spot
--   ADD COLUMN `price_raw`  decimal(18,4) DEFAULT NULL COMMENT '不复权现价=原 new_price 口径',
--   ADD COLUMN `price_qfq`  decimal(18,4) DEFAULT NULL COMMENT '与qfq日线对齐的复权参考价(由分析层JOIN回填,非快照原生)';
-- 未授权前：不改表，只在文档/SQL 层固定“趋势看 qfq 日线、现价看快照 new_price”的读取约定。

-- 10.2 最新截面两套价格口径差异规模（只读；2026-11-10 实测 total=4144 / no_qfq_match=2 / |差|>5%=221）
SELECT COUNT(*) AS total,
       SUM(k.close IS NULL) AS no_qfq_match,
       SUM(k.close IS NOT NULL AND ABS((s.new_price - k.close) / NULLIF(k.close, 0)) > 0.05) AS diff_gt_5pct
FROM cn_stock_selection s
LEFT JOIN cn_stock_daily_kline k
  ON k.code = s.code AND k.date = s.date AND k.adjust = 'qfq'
WHERE s.date = (SELECT MAX(date) FROM cn_stock_selection);

-- 10.3 差异最大样本（只读；用于定位差异成因=除权除息/次新/复权未对齐，不据此回写价格）
SELECT s.code, s.name, s.new_price, k.close AS qfq_close,
       ROUND((s.new_price - k.close) / NULLIF(k.close, 0) * 100, 2) AS diff_pct
FROM cn_stock_selection s
JOIN cn_stock_daily_kline k ON k.code = s.code AND k.date = s.date AND k.adjust = 'qfq'
WHERE s.date = (SELECT MAX(date) FROM cn_stock_selection)
  AND k.close IS NOT NULL
ORDER BY ABS((s.new_price - k.close) / NULLIF(k.close, 0)) DESC
LIMIT 15;


-- =============================================================================
-- 只读自检：确认上述 SELECT 可在不改库前提下运行；新增表/改表一律回到评审与备份流程。
-- =============================================================================
