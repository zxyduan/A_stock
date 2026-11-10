-- =============================================================================
-- gap_valuation_ddl.sql  #2 估值截面时序表 cn_stock_valuation_daily【本轮受控授权创建】
-- 纪律（重要）：
--   * 仅 CREATE TABLE IF NOT EXISTS 独立新表；不含 ALTER / DROP / UPDATE / DELETE，
--     不触碰既有旧三表与已建五张缺口表；
--   * 执行前已完成整库备份 backup/instockdb_20261110_1529.sql.gz（GZIP_OK / BACKUP_OK）；
--   * 列集与 jobs/em_valuation_loader.py 的 COLS 严格对齐；PK(code,date) 幂等，重复日 upsert 刷新；
--   * 只做“当日截面 -> 时序”增量，不回填历史长序列（免费长序列端点前期已证伪）；
--   * 非正 / NULL 估值在采集层默认剔除，库内不保留非正值；分位由分析层滚动计算；
--   * 不挂 cron：首次写入人工受控触发，后续是否接入收盘作业另行授权。
-- 一次性幂等执行：
--   docker exec -i InStockDbService mariadb --default-character-set=utf8mb4 -uroot -proot instockdb \
--     < /data/instock/ops/gap_valuation_ddl.sql
-- 回滚（独立新表、单独授权后执行；默认不跑）：
--   DROP TABLE IF EXISTS `cn_stock_valuation_daily`;
-- =============================================================================

CREATE TABLE IF NOT EXISTS `cn_stock_valuation_daily` (
  `code`      varchar(10)  NOT NULL COMMENT '证券代码(沪深A股普通股;采集侧按白名单过滤)',
  `date`      date         NOT NULL COMMENT '截面日期(=cn_stock_selection.date,收盘日)',
  `pe9`       decimal(18,6) DEFAULT NULL COMMENT '取自 selection.pe9;亏损股非正值采集层已剔除',
  `pbnewmrq`  decimal(18,6) DEFAULT NULL COMMENT '取自 selection.pbnewmrq(最新MRQ)',
  `ps9`       decimal(18,6) DEFAULT NULL COMMENT '取自 selection.ps9',
  `source`    varchar(24)  NOT NULL DEFAULT 'FROM_SELECTION_SNAPSHOT',
  PRIMARY KEY (`code`, `date`),
  KEY `idx_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='#2估值截面时序;仅每日增量不回填;PK(code,date);非正/NULL采集层剔除';
