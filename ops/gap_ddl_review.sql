-- =============================================================================
-- gap_ddl_review.sql  P1 缺口补全新表【审阅草案，禁止直接整段 source】
-- 对应采集器: jobs/em_dividend_loader.py / em_index_kline_loader.py / em_event_loader.py
-- 目标库: instockdb (MariaDB, InnoDB, utf8mb4)
--
-- 执行纪律（实施阶段、用户拍板后才放开；本仓库默认不执行任何写库）：
--   1. 先备份: bash /data/instock/ops/backup_db_enhanced.sh，确认 gzip -t 通过、文件存在。
--   2. 逐段单独执行（建议 mariadb --default-character-set=utf8mb4 -uroot -proot instockdb），
--      每段后跑文末只读校验；新表独立，不 ALTER 任何现有在线表。
--   3. 采集器默认 DRY_RUN；建表后先 *_DRY_RUN=1 看样例，再 LIMIT 小批量灰度，最后全量。
--   4. 回滚（新表独立、互不影响旧表）：
--      DROP TABLE IF EXISTS cn_stock_dividend;
--      DROP TABLE IF EXISTS cn_index_daily;
--      DROP TABLE IF EXISTS cn_stock_event;
--   5. 列名与采集器 COLS 严格一致；未建模原始响应保留在 raw_json，禁止臆造业务列。
-- =============================================================================


-- -----------------------------------------------------------------------------
-- P1-1 #3 分红送配与股息率事件表（源 RPT_SHAREBONUS_DET；事件型，INSERT IGNORE）
-- 主键含 plan_notice_date 作为“未实施预案”去重锚点；实施类以 ex_dividend_date 区分。
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cn_stock_dividend` (
  `code`               varchar(10)  NOT NULL COMMENT '证券代码',
  `secucode`           varchar(16)  DEFAULT NULL COMMENT 'SECUCODE 如 600519.SH',
  `name`               varchar(32)  DEFAULT NULL,
  `report_date`        date         DEFAULT NULL COMMENT '报告期截止日',
  `plan_notice_date`   date         DEFAULT NULL COMMENT '预案/方案公告日(去重锚点)',
  `equity_record_date` date         DEFAULT NULL COMMENT '股权登记日',
  `ex_dividend_date`   date         DEFAULT NULL COMMENT '除权除息日',
  `pretax_bonus_rmb`   decimal(14,6) DEFAULT NULL COMMENT '源 PRETAX_BONUS_RMB 派息原值(每10股/每股口径待抽样核对,禁止直接当每股;原始响应见raw_json)',
  `bonus_ratio`        decimal(12,6) DEFAULT NULL COMMENT '源 BONUS_RATIO 送股比例原值',
  `it_ratio`           decimal(12,6) DEFAULT NULL COMMENT '源 IT_RATIO 转增比例原值',
  `divident_ratio`     decimal(12,6) DEFAULT NULL COMMENT '源 DIVIDENT_RATIO 股息率原值(小数, 如0.0069≈0.69%)',
  `assign_progress`    varchar(32)  DEFAULT NULL COMMENT '方案进度',
  `plan_profile`       varchar(255) DEFAULT NULL COMMENT '方案文本',
  `total_shares`       decimal(22,2) DEFAULT NULL,
  `basic_eps`          decimal(14,4) DEFAULT NULL,
  `bvps`               decimal(14,4) DEFAULT NULL,
  `source`             varchar(32)  DEFAULT 'EM_RPT_SHAREBONUS_DET',
  `raw_json`           json         DEFAULT NULL COMMENT '原始响应留存',
  PRIMARY KEY (`code`,`plan_notice_date`,`ex_dividend_date`),
  KEY `idx_exdate` (`ex_dividend_date`),
  KEY `idx_report` (`report_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分红送配事件与股息率(东财RPT_SHAREBONUS_DET)';


-- -----------------------------------------------------------------------------
-- P1-2 #6 宽基指数日线（源 push2his kline；指数无复权, adjust 固定 raw）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cn_index_daily` (
  `index_code` varchar(12)  NOT NULL,
  `name`       varchar(32)  DEFAULT NULL,
  `date`       date         NOT NULL,
  `open`       decimal(18,4) DEFAULT NULL,
  `close`      decimal(18,4) DEFAULT NULL,
  `high`       decimal(18,4) DEFAULT NULL,
  `low`        decimal(18,4) DEFAULT NULL,
  `volume`     bigint       DEFAULT NULL COMMENT '源 f56 成交量原值(单位以源口径为准)',
  `amount`     decimal(22,2) DEFAULT NULL COMMENT '源 f57 成交额原值(元, 实写前抽样核对量级)',
  `adjust`     varchar(8)   NOT NULL DEFAULT 'raw',
  `source`     varchar(32)  DEFAULT 'EM_PUSH2HIS_KLINE',
  PRIMARY KEY (`index_code`,`date`,`adjust`),
  KEY `idx_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='宽基指数日K(东财push2his kline)';


-- -----------------------------------------------------------------------------
-- P1-3 #8a 限售解禁事件（源 RPT_LIFT_STAGE；统一事件表，本期仅 lockup_unlock）
-- 预留 event_type 供后续 holder_change/repurchase，但本期不采集（报表未定位/排除）。
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cn_stock_event` (
  `code`          varchar(10)  NOT NULL,
  `name`          varchar(32)  DEFAULT NULL,
  `event_date`    date         NOT NULL,
  `event_type`    varchar(24)  NOT NULL COMMENT 'lockup_unlock;预留 holder_change/repurchase',
  `amount_shares` decimal(22,2) DEFAULT NULL COMMENT '源 FREE_SHARES 原值(单位疑万股, 实写前抽样核对)',
  `amount_ratio`  decimal(12,6) DEFAULT NULL COMMENT '源 FREE_RATIO/TOTAL_RATIO 原值(小数或百分比口径待核)',
  `event_mktcap`  decimal(22,2) DEFAULT NULL COMMENT '源 LIFT_MARKET_CAP 原值(单位疑万元, 实写前抽样核对)',
  `detail`        varchar(128) DEFAULT NULL COMMENT '源 FREE_SHARES_TYPE 解禁类型明细',
  `source`        varchar(32)  DEFAULT 'EM_RPT_LIFT_STAGE',
  `raw_json`      json         DEFAULT NULL,
  PRIMARY KEY (`code`,`event_date`,`event_type`,`detail`(64)),
  KEY `idx_date_type` (`event_date`,`event_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='个股事件表(本期仅解禁;其余类型预留不采)';


-- =============================================================================
-- 建表后【只读校验】（不写库，仅确认结构与空表状态）
-- =============================================================================
-- SHOW CREATE TABLE cn_stock_dividend;
-- SHOW CREATE TABLE cn_index_daily;
-- SHOW CREATE TABLE cn_stock_event;
-- SELECT 'cn_stock_dividend' t, COUNT(*) FROM cn_stock_dividend
-- UNION ALL SELECT 'cn_index_daily', COUNT(*) FROM cn_index_daily
-- UNION ALL SELECT 'cn_stock_event', COUNT(*) FROM cn_stock_event;
-- 重复主键抽检(应全 0)：
-- SELECT 'dividend' t, COUNT(*) FROM (SELECT code,plan_notice_date,ex_dividend_date,COUNT(*) c
--   FROM cn_stock_dividend GROUP BY 1,2,3 HAVING c>1) x
-- UNION ALL SELECT 'index', COUNT(*) FROM (SELECT index_code,date,COUNT(*) c
--   FROM cn_index_daily GROUP BY 1,2 HAVING c>1) x
-- UNION ALL SELECT 'event', COUNT(*) FROM (SELECT code,event_date,event_type,detail,COUNT(*) c
--   FROM cn_stock_event GROUP BY 1,2,3,4 HAVING c>1) x;
