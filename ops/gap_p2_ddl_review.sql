-- =============================================================================
-- gap_p2_ddl_review.sql  P2 缺口补全新表【审阅草案，禁止直接整段 source】
-- 配套: jobs/em_holder_loader.py(#8b) / jobs/em_org_holding_loader.py(#8c)
-- 目标库: instockdb (MariaDB, InnoDB, utf8mb4)；纪律同 gap_ddl_review.sql：
--   先备份 -> 逐段人工执行 -> 文末只读校验；采集器默认 DRY_RUN，APPLY 前必须表已存在。
-- 本文件只含本轮字段已实测确认的两张表；#1 财务与 #11 见文末“未纳入”说明。
-- =============================================================================


-- -----------------------------------------------------------------------------
-- P2-A #8b 股东户数时序（源 RPT_F10_EH_HOLDERNUM；季频/不定期；PK code+end_date）
-- 单位：股东户数为“户”；持股比例/金额单位以 raw_json 抽样核对，实写前勿下结论。
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cn_stock_holder` (
  `code`             varchar(10)   NOT NULL,
  `name`             varchar(32)   DEFAULT NULL,
  `end_date`         date          NOT NULL COMMENT '报告期末',
  `holder_total_num` bigint        DEFAULT NULL COMMENT '股东户数(户)',
  `num_change`       bigint        DEFAULT NULL COMMENT '较上期增减(户)',
  `total_num_ratio`  float         DEFAULT NULL COMMENT '源 TOTAL_NUM_RATIO 户数环比(口径待核)',
  `avg_total_shares` decimal(22,4) DEFAULT NULL COMMENT '源 AVG_TOTAL_SHARES 户均持股(单位待核)',
  `avg_hold_amt`     decimal(22,2) DEFAULT NULL COMMENT '源 AVG_HOLD_AMT 户均持股市值(单位待核)',
  `notice_date`      date          DEFAULT NULL COMMENT '披露日',
  `source`           varchar(40)   DEFAULT 'EM_RPT_F10_EH_HOLDERNUM',
  `raw_json`         json          DEFAULT NULL,
  PRIMARY KEY (`code`,`end_date`),
  KEY `idx_end_date` (`end_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='股东户数时序(东财F10,季频/不定期)';


-- -----------------------------------------------------------------------------
-- P2-B #8c 机构持仓明细（源 RPT_MAINDATA_MAIN_POSITIONDETAILS；季频）
-- 粒度：一行=某报告期某机构持有某股票；PK(code,report_date,holder_name)。
-- 汇总(机构家数/合计占比)由分析层按 code,report_date 聚合，不在表内冗余。
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cn_stock_org_holding` (
  `code`           varchar(10)   NOT NULL,
  `name`           varchar(32)   DEFAULT NULL,
  `report_date`    date          NOT NULL,
  `holder_name`    varchar(64)   NOT NULL,
  `org_type`       varchar(24)   DEFAULT NULL COMMENT '基金/QFII/社保/券商等源 ORG_TYPE',
  `total_shares`  decimal(22,4) DEFAULT NULL COMMENT '源 TOTAL_SHARES(股,单位待核)',
  `shares_ratio`   decimal(12,6) DEFAULT NULL COMMENT '源 TOTAL_SHARES_RATIO 占总股本比例(口径待核)',
  `netasset_ratio` decimal(12,6) DEFAULT NULL COMMENT '源 NETASSET_RATIO 占其净值比例(口径待核)',
  `hold_mktcap`    decimal(22,2) DEFAULT NULL COMMENT '源 HOLD_MARKET_CAP 持仓市值(单位待核)',
  `source`         varchar(40)   DEFAULT 'EM_RPT_MAINDATA_MAIN_POSITIONDETAILS',
  `raw_json`       json          DEFAULT NULL,
  PRIMARY KEY (`code`,`report_date`,`holder_name`),
  KEY `idx_report_date` (`report_date`),
  KEY `idx_holder` (`holder_name`(32))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='机构持仓明细(东财主报表,季频,一行一机构)';


-- =============================================================================
-- 建表后【只读校验】
-- -----------------------------------------------------------------------------
-- SELECT 'holder' t, COUNT(*) FROM cn_stock_holder
-- UNION ALL SELECT 'org_holding', COUNT(*) FROM cn_stock_org_holding;
-- SELECT code,end_date,holder_total_num,num_change,total_num_ratio
--   FROM cn_stock_holder ORDER BY end_date DESC LIMIT 5;
-- SELECT code,report_date,org_type,holder_name,shares_ratio,hold_mktcap
--   FROM cn_stock_org_holding ORDER BY report_date DESC LIMIT 5;


-- =============================================================================
-- 【未纳入本批代码的项 —— 依据 2026-11-10 只读实测】
-- -----------------------------------------------------------------------------
-- #1 季度财务三表/主指标：端点可达但需先定稿，不在本批建采集器：
--   * RPT_F10_FINANCE_MAINFINADATA 宽 165 字段(含 EPSJB/ROEJQ/XSMLL/XSJLL/ZCFZL/
--     DJD_TOI_YOY/DJD_DPNP_YOY/CHZZL/CASH_RATIO/CL_TL)；
--   * RPT_DMSK_FN_INCOME 46 / BALANCE 57 / CASHFLOW 48 字段，三表独立、按(code,report_date)
--     关联；金额疑似“元”，比率带 _RATIO 后缀但小数/百分号口径待核；金融行业(银行/保险/券商)
--     缺少工业科目、自带专用科目，需列裁剪；BALANCE 实测无 GOODWILL 字段(商誉暂不采)。
--   * 落地前先出“字段映射 + 单位抽样 + 金融裁剪”评审，再决定单宽表 ON DUPLICATE 补列
--     还是主表+三附表；当前仅保留需求方案中的 cn_stock_financial_quarter 草案结构。
--
-- #11 资金流更长周期：push2his fflow/daykline/get 在 lmt=120/300/1000 下 data=None，
--   口径与窗口不可靠；现有 cn_stock_fund_flow 已含在线作业 3/5/10 日累计，
--   本批不建外部资金流历史采集器；20 日累计与单位说明列为本地治理/字段级改进，另行评审。
-- =============================================================================
