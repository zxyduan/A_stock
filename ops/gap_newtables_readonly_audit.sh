#!/usr/bin/env bash
# =============================================================================
# gap_newtables_readonly_audit.sh  五张缺口新表【只读巡检】(2026-11-10)
# 覆盖表:
#   cn_index_daily / cn_stock_event / cn_stock_holder / cn_stock_dividend / cn_stock_org_holding
# 红线: 本脚本只执行 SELECT / information_schema 查询, 绝不 INSERT/UPDATE/DELETE/DDL,
#       不重启、不改 cron；可在宿主随时复跑用于验收幂等性/口径残留/新鲜度。
# 与 ops 下既有 db_quality_audit_extended.sh 分工: 那份巡检旧主链(kline/selection/fund_flow
#       /indicators 等), 本脚本只看本轮新建五表；列名均经 information_schema 实测, 不臆造。
# 用法(宿主 aliyun):
#   bash /data/instock/ops/gap_newtables_readonly_audit.sh
# 备注: Windows 编辑后上传先转 LF: sed -i 's/\r$//' gap_newtables_readonly_audit.sh
# =============================================================================
set +e

M="docker exec InStockDbService mariadb --default-character-set=utf8mb4 -uroot -proot instockdb -t"

echo "############ A. 五新表规模矩阵: 行数 / 代码数 / 时间区间 ############"
$M -e "
SELECT 'index_daily'  AS tbl, COUNT(*) rows_cnt, COUNT(DISTINCT index_code) codes,
       MIN(date) first_d, MAX(date) last_d FROM cn_index_daily
UNION ALL SELECT 'event',        COUNT(*), COUNT(DISTINCT code), MIN(event_date), MAX(event_date) FROM cn_stock_event
UNION ALL SELECT 'holder',      COUNT(*), COUNT(DISTINCT code), MIN(end_date),  MAX(end_date)  FROM cn_stock_holder
UNION ALL SELECT 'dividend',    COUNT(*), COUNT(DISTINCT code), MIN(report_date), MAX(report_date) FROM cn_stock_dividend
UNION ALL SELECT 'org_holding', COUNT(*), COUNT(DISTINCT code), MIN(report_date), MAX(report_date) FROM cn_stock_org_holding;
"

echo; echo "############ B. 候选唯一键重复行数(应趋近0;事件/股东为粗键,披露用不自动删除) ############"
$M -e "
SELECT 'index_daily(code,date,adjust)' tbl, COUNT(*) dup_rows FROM
  (SELECT index_code,date,adjust,COUNT(*) c FROM cn_index_daily GROUP BY index_code,date,adjust HAVING c>1) x
UNION ALL SELECT 'dividend(code,report_date,plan_notice_date)', COUNT(*) FROM
  (SELECT code,report_date,plan_notice_date,COUNT(*) c FROM cn_stock_dividend GROUP BY code,report_date,plan_notice_date HAVING c>1) x
UNION ALL SELECT 'event(code,event_date,event_type)', COUNT(*) FROM
  (SELECT code,event_date,event_type,COUNT(*) c FROM cn_stock_event GROUP BY code,event_date,event_type HAVING c>1) x
UNION ALL SELECT 'holder(code,end_date)', COUNT(*) FROM
  (SELECT code,end_date,COUNT(*) c FROM cn_stock_holder GROUP BY code,end_date HAVING c>1) x
UNION ALL SELECT 'org(code,report_date,holder_name)', COUNT(*) FROM
  (SELECT code,report_date,holder_name,COUNT(*) c FROM cn_stock_org_holding GROUP BY code,report_date,holder_name HAVING c>1) x;
"

echo; echo "############ C. 代码首位前缀分布(0/3/6=白名单主段;9=北交所/老三板;只读披露不删) ############"
$M -e "
SELECT 'event' t, LEFT(code,1) seg, COUNT(*) n FROM cn_stock_event       GROUP BY LEFT(code,1)
UNION ALL SELECT 'holder', LEFT(code,1), COUNT(*) FROM cn_stock_holder   GROUP BY LEFT(code,1)
UNION ALL SELECT 'dividend', LEFT(code,1), COUNT(*) FROM cn_stock_dividend GROUP BY LEFT(code,1)
UNION ALL SELECT 'org', LEFT(code,1), COUNT(*) FROM cn_stock_org_holding GROUP BY LEFT(code,1)
ORDER BY t, seg;
"

echo; echo "############ C2. 未命中A股白名单前缀计数(含北交所920/待核302,689/历史残留;只读披露,不自动删除) ############"
$M -e "
SELECT 'event_nonA' k, COUNT(*) n FROM cn_stock_event
 WHERE code NOT REGEXP '^(000|001|002|003|300|301|600|601|603|605|688)'
UNION ALL SELECT 'holder_nonA', COUNT(*) FROM cn_stock_holder
 WHERE code NOT REGEXP '^(000|001|002|003|300|301|600|601|603|605|688)'
UNION ALL SELECT 'dividend_nonA', COUNT(*) FROM cn_stock_dividend
 WHERE code NOT REGEXP '^(000|001|002|003|300|301|600|601|603|605|688)'
UNION ALL SELECT 'org_nonA', COUNT(*) FROM cn_stock_org_holding
 WHERE code NOT REGEXP '^(000|001|002|003|300|301|600|601|603|605|688)';
"

echo; echo "############ D. 分红口径: 进度分布 / 除息日缺失 / 报告期Top ############"
$M -e "SELECT assign_progress, COUNT(*) n FROM cn_stock_dividend GROUP BY assign_progress;"
$M -e "SELECT COUNT(*) total, COUNT(DISTINCT code) codes, SUM(ex_dividend_date IS NULL) ex_date_null FROM cn_stock_dividend;"
$M -e "SELECT report_date, COUNT(*) rows_ FROM cn_stock_dividend GROUP BY report_date ORDER BY report_date DESC LIMIT 8;"

echo; echo "############ E. 股东户数报告期分布(end_date=报告期;季频时序) ############"
$M -e "SELECT end_date, COUNT(*) rows_, COUNT(DISTINCT code) codes FROM cn_stock_holder GROUP BY end_date ORDER BY end_date DESC LIMIT 8;"

echo; echo "############ F. 指数日线: 指数/复权口径清单 ############"
$M -e "SELECT index_code, name, adjust, COUNT(*) rows_, MIN(date) first_d, MAX(date) last_d FROM cn_index_daily GROUP BY index_code,name,adjust ORDER BY index_code;"

echo; echo "############ G. 旧主表行数基线(只读;对比应逐位不变,佐证本轮零写入) ############"
$M -e "
SELECT 'kline' tbl, COUNT(*) rows_cnt FROM cn_stock_daily_kline
UNION ALL SELECT 'selection', COUNT(*) FROM cn_stock_selection
UNION ALL SELECT 'fund_flow', COUNT(*) FROM cn_stock_fund_flow;
"

echo; echo "############ H. #1财务目标表存在性(默认0=未建表,未授权放量前应保持0) ############"
$M -e "SELECT COUNT(*) fin_table_exists FROM information_schema.tables WHERE table_schema='instockdb' AND table_name='cn_stock_financial_quarter';"

echo; echo "############ I. 五新表索引定义(只读;MariaDB用INDEX_NAME,非Key_name) ############"
$M -e "
SELECT table_name, index_name, GROUP_CONCAT(column_name ORDER BY seq_in_index) cols, non_unique
FROM information_schema.STATISTICS
WHERE table_schema='instockdb' AND table_name IN
  ('cn_index_daily','cn_stock_event','cn_stock_holder','cn_stock_dividend','cn_stock_org_holding')
GROUP BY table_name, index_name, non_unique
ORDER BY table_name, index_name;
"

echo; echo "############ J. 未命中白名单前缀成因细分 + holder季末合规(只读;解释C2来源,不删除) ############"
$M -e "
SELECT 'dividend' t, LEFT(code,3) seg, COUNT(*) n FROM cn_stock_dividend
 WHERE code NOT REGEXP '^(000|001|002|003|300|301|600|601|603|605|688)' GROUP BY LEFT(code,3)
UNION ALL SELECT 'event', LEFT(code,3), COUNT(*) FROM cn_stock_event
 WHERE code NOT REGEXP '^(000|001|002|003|300|301|600|601|603|605|688)' GROUP BY LEFT(code,3)
ORDER BY t, n DESC;"
$M -e "
SELECT CASE WHEN RIGHT(end_date,5) IN ('03-31','06-30','09-30','12-31') THEN 'quarter_end' ELSE 'other_nonquarter' END kind,
       COUNT(*) rows_, COUNT(DISTINCT code) codes
FROM cn_stock_holder GROUP BY kind;
"

echo; echo "############ 巡检完成: 以上全部为只读查询, 未做任何写操作。NEW_TABLES_AUDIT_DONE ############"
