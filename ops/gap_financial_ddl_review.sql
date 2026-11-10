-- =============================================================================
-- gap_financial_ddl_review.sql  #1 季度财务关键科目【评审草案，禁止直接整段 source】
-- 配套采集器: jobs/em_financial_loader.py（默认 FIN_DRY_RUN=1，本批不建表、不 APPLY）
-- 依据: gap/docs/F1_季度财务落地规格_字段映射单位金融裁剪_20261110.md
-- 目标库: instockdb (MariaDB, InnoDB, utf8mb4)
--
-- 执行纪律（用户另行拍板放量时才放开）：
--   1) 先 bash /data/instock/ops/backup_db_enhanced.sh 并 gzip -t 校验；
--   2) 逐段人工执行、执行后跑文末只读校验；新表独立，不 ALTER 任何现有表；
--   3) 金额单位=元（2026-11-10 600519 探针实测量级 1e10~1e11）；比率口径按列 COMMENT；
--   4) 写库建议 ON DUPLICATE KEY UPDATE（同报告期补录/修订刷新），采集器当前写库段为占位；
--   5) 回滚：DROP TABLE IF EXISTS cn_stock_financial_quarter;
--
-- 已实测不采 / 待核，禁止臆造：
--   * BALANCE 无 GOODWILL 字段 -> 不设 goodwill 列；
--   * CURRENT_RATIO=509 口径存疑 -> current_ratio 仅存原值、放量前不进打分；
--   * 保险 EV/PEV 无源字段；NBV_LIFE/NBV_RATE 需保险股抽样确认非空后启用；
--   * 有息负债非现成科目，派生项本期不入列。
-- =============================================================================

CREATE TABLE IF NOT EXISTS `cn_stock_financial_quarter` (
  `code`                varchar(10)   NOT NULL COMMENT '证券代码',
  `name`                varchar(32)   DEFAULT NULL,
  `report_date`         date          NOT NULL COMMENT '报告期截止日(利润/现金流为年初至期末累计;资产负债为时点数)',
  `report_type`         varchar(8)    DEFAULT NULL COMMENT 'Q1/H1/Q3/AR(源 REPORT_TYPE/REPORT_DATE_NAME)',
  `report_ann_date`    date          DEFAULT NULL COMMENT '披露日 NOTICE_DATE',
  `industry_code`      varchar(16)   DEFAULT NULL,
  `industry_name`      varchar(32)   DEFAULT NULL,
  `is_financial`        tinyint       NOT NULL DEFAULT 0 COMMENT '1=银行/保险/券商,工业科目留空',
  -- 盈利(元,累计;保源原值不缩放)
  `rev_total`          decimal(22,2) DEFAULT NULL COMMENT '营业总收入(元): INCOME.TOTAL_OPERATE_INCOME,兜底 MAIN.TOTALOPERATEREVE',
  `rev_yoy`            float         DEFAULT NULL COMMENT '营收同比%(源 TOTALOPERATEREVETZ,百分数值)',
  `np_parent`          decimal(22,2) DEFAULT NULL COMMENT '归母净利润(元,累计)',
  `np_yoy`             float         DEFAULT NULL COMMENT '归母净利同比%',
  `np_deduct`          decimal(22,2) DEFAULT NULL COMMENT '扣非归母净利(元,累计)',
  `np_deduct_yoy`      float         DEFAULT NULL,
  `eps_basic`          float         DEFAULT NULL COMMENT '基本EPS(元) MAIN.EPSJB',
  -- 质量比率(口径各异,勿统一当%: ROE/毛利/净利/负债率为百分数值;周转率/现金比率为倍数)
  `roe_weight`         float         DEFAULT NULL COMMENT '加权ROE%(MAIN.ROEJQ,24.47=24.47%)',
  `gross_margin`       float         DEFAULT NULL COMMENT '毛利率%(MAIN.XSMLL)',
  `net_margin`         float         DEFAULT NULL COMMENT '净利率%(MAIN.XSJLL)',
  `debt_asset_ratio`   float         DEFAULT NULL COMMENT '资产负债率%(MAIN.ZCFZL/BALANCE.DEBT_ASSET_RATIO)',
  `current_ratio`      float         DEFAULT NULL COMMENT '流动比率;口径(倍/%)待核,先存原值不打分',
  `cash_ratio`         float         DEFAULT NULL COMMENT '现金比率(倍) MAIN.CASH_RATIO',
  `inv_turnover`       float         DEFAULT NULL COMMENT '存货周转率(倍) MAIN.CHZZL',
  -- 现金流(元,累计)
  `ocf`                decimal(22,2) DEFAULT NULL COMMENT '经营现金流净额(元) CF.NETCASH_OPERATE',
  `ocf_to_np`          float         DEFAULT NULL COMMENT 'OCF/归母净利(倍,脚本派生)',
  `sales_cash`         decimal(22,2) DEFAULT NULL COMMENT '销售商品提供劳务收到现金(元) CF.SALES_SERVICES',
  -- 资产负债(元,时点;工业口径,金融置空)
  `cash_monetary`      decimal(22,2) DEFAULT NULL COMMENT '货币资金(元) BALANCE.MONETARYFUNDS',
  `accounts_receivable` decimal(22,2) DEFAULT NULL COMMENT '应收账款(元) BALANCE.ACCOUNTS_RECE',
  `inventory`          decimal(22,2) DEFAULT NULL COMMENT '存货(元) BALANCE.INVENTORY',
  `fixed_asset`        decimal(22,2) DEFAULT NULL COMMENT '固定资产(元) BALANCE.FIXED_ASSET',
  `accounts_payable`  decimal(22,2) DEFAULT NULL COMMENT '应付账款(元) BALANCE.ACCOUNTS_PAYABLE',
  `total_assets`       decimal(22,2) DEFAULT NULL COMMENT '总资产(元) BALANCE.TOTAL_ASSETS',
  `total_liab`         decimal(22,2) DEFAULT NULL COMMENT '总负债(元) BALANCE.TOTAL_LIABILITIES',
  `total_equity`       decimal(22,2) DEFAULT NULL COMMENT '所有者权益(元) BALANCE.TOTAL_EQUITY',
  -- 金融专用(仅金融行;EV/PEV无源,不采)
  `fin_loans`          decimal(22,2) DEFAULT NULL COMMENT '贷款总额(银行) MAIN.GROSSLOANS',
  `fin_deposits`       decimal(22,2) DEFAULT NULL COMMENT '存款总额(银行) MAIN.TOTALDEPOSITS',
  `fin_npl_ratio`      float         DEFAULT NULL COMMENT '不良贷款率 MAIN.NONPERLOAN',
  `fin_car`            float         DEFAULT NULL COMMENT '资本充足率 MAIN.FIRST_ADEQUACY_RATIO',
  `fin_nbv_life`       decimal(22,2) DEFAULT NULL COMMENT '寿险NBV(元) MAIN.NBV_LIFE,保险股抽样确认后启用',
  `fin_nbv_rate`      float         DEFAULT NULL COMMENT 'NBV增速% MAIN.NBV_RATE',
  `source`             varchar(24)   DEFAULT 'EM_DATACENTER',
  `raw_json`           json          DEFAULT NULL COMMENT '四报表原始记录合并留存',
  `updated_at`        timestamp     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`code`,`report_date`),
  KEY `idx_report_date` (`report_date`),
  KEY `idx_industry` (`industry_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='季度财务关键科目(元;累计;金融裁剪;#1;评审草案)';


-- =============================================================================
-- 建表后【只读校验】（放量执行后使用；平时不运行）
-- -----------------------------------------------------------------------------
-- SELECT COUNT(*), COUNT(DISTINCT code), MIN(report_date), MAX(report_date)
--   FROM cn_stock_financial_quarter;
-- SELECT report_type, COUNT(*) FROM cn_stock_financial_quarter GROUP BY report_type;
-- SELECT code,report_date,rev_total,np_parent,ocf,total_assets,roe_weight
--   FROM cn_stock_financial_quarter WHERE code='600519' ORDER BY report_date DESC LIMIT 6;
-- SELECT is_financial, COUNT(*) FROM cn_stock_financial_quarter GROUP BY is_financial;
