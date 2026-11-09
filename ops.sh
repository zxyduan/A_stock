#!/usr/bin/env bash
#==========================================================================
# InStock 统一运维脚本（宿主 /data/instock/ops.sh，bash 执行）
# 用法: bash ops.sh <子命令> [参数]
# 只读/安全操作直接跑; 写操作(backup-restore/cache-clear/job-*/kline-run)有明确子命令
#==========================================================================
set +e

COMPOSE_DIR=/data/instock
APP=InStock                       # 应用容器
DB=InStockDbService               # 数据库容器
DB_USER=root
DB_PASS=root
DB_NAME=instockdb
APP_DIR=/data/InStock
JOB_DIR=/data/InStock/instock/job
CACHE_HOST=/data/instock/app/cache
KLINE_PY=instock/cache/kline_history_loader.py

c(){ docker "$@"; }
hr(){ echo "----------------------------------------------------------------------"; }

db_sql(){ docker exec "$DB" mariadb --default-character-set=utf8mb4 -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$1"; }
app_py(){ docker exec "$APP" python3 "$@"; }
job_py(){ docker exec "$APP" python3 "$JOB_DIR/$1"; shift 2>/dev/null; }

usage(){
cat <<'EOF'
InStock 运维子命令
  【查看/只读】
  status            服务/进程/Web探活/Supervisor/资源 综合状态
  health            status + 核心表行数 + 质量核查 + 备份与磁盘
  tables            列出全部表及 InnoDB 估算行数
  counts            核心表精确行数与最新交易日
  verify            历史日线质量核查(重复/缺失/空值/分布/抽样)
  kline-status      历史入库进程/断点/表覆盖
  kline-log [N]     跟踪历史入库日志(默认 tail 40)
  logs-docker [N]   应用容器 stdout 日志(默认 tail 120)
  logs-app          作业与Web落盘日志尾部
  backup-list       列出历史备份
  cache-list        历史pickle缓存目录占用

  【进入容器/数据库】(需先 ssh 登录到主机再执行, 交互用 -t)
  enter             进入应用容器 shell: docker exec -it InStock sh
  db                进入 MariaDB 交互客户端: instockdb
  sql "<SQL>"       非交互执行一条 SQL

  【数据作业: 无参=最近交易日; save_nph 类不要传历史日期(before=True会空跑)】
  job-basic         盘中快照: basic_data_daily_job.py (个股+ETF实时)
  job-close         收盘总作业: execute_daily_job.py (基础+综合+资金流+盘后)
  job-afterclose    盘后专项: basic_data_after_close_daily_job.py (大宗/尾盘抢筹)
  job-run <py> [参数...]  手动跑指定作业并透传参数(如 job-run basic_data_daily_job.py)

  【自建历史日线入库 cn_stock_daily_kline】
  kline-run [起20210101] [并发10]   后台断点续跑(INSERT IGNORE幂等)
  kline-stop                        停止正在跑的入库进程(已提交行保留)

  【备份与恢复】
  backup-now        立即做一次 gzip 逻辑备份
  backup-restore <备份.gz>          只打印恢复命令(不执行)
  backup-restore --confirm <备份.gz> 真正用备份覆盖 instockdb(危险, 谨慎)

  【重启/缓存】
  restart-app       重启应用容器(不影响DB与已持久化数据)
  restart-db        重启数据库容器
  restart-all       compose restart 两服务
  cache-clear       清空历史pickle缓存(等价月度清理; 不影响MySQL入库数据)

  【其它】
  help              本帮助
EOF
}

cmd_status(){
  hr; echo "[1] compose"; c compose -f "$COMPOSE_DIR/docker-compose.yml" ps
  hr; echo "[2] Web 探活"; curl -sS -m5 -o /dev/null -w "http://127.0.0.1:9988/instock/ -> %{http_code}\n" http://127.0.0.1:9988/instock/
  hr; echo "[3] supervisor 程序"; docker exec "$APP" supervisorctl status
  hr; echo "[4] 关键进程"; docker top "$APP" | grep -E "web_service|cron -f|kline_history" || echo "(无批处理进程)"
  hr; echo "[5] 资源"; free -h; swapon --show; df -h /
  hr; echo "[6] 镜像"; docker images --format '{{.Repository}}:{{.Tag}}  {{.ID}}  {{.Size}}' | head
}

cmd_counts(){
  db_sql "SELECT 'cn_stock_spot' AS t, COUNT(*) cnt, MAX(date) latest FROM cn_stock_spot
UNION ALL SELECT 'cn_etf_spot', COUNT(*), MAX(date) FROM cn_etf_spot
UNION ALL SELECT 'cn_stock_selection', COUNT(*), MAX(date) FROM cn_stock_selection
UNION ALL SELECT 'cn_stock_fund_flow', COUNT(*), MAX(date) FROM cn_stock_fund_flow
UNION ALL SELECT 'cn_stock_daily_kline', COUNT(*), MAX(date) FROM cn_stock_daily_kline;"
}

cmd_tables(){
  db_sql "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='$DB_NAME' ORDER BY table_name;"
}

cmd_verify(){
  echo "== 主键唯一性(应相等) =="
  db_sql "SELECT COUNT(*) total_rows, COUNT(DISTINCT code,date,adjust) distinct_key FROM cn_stock_daily_kline;"
  echo "== spot 缺失到历史表的代码(应0) =="
  db_sql "SELECT COUNT(*) missing_codes FROM (SELECT DISTINCT code FROM cn_stock_spot) s
 LEFT JOIN (SELECT DISTINCT code FROM cn_stock_daily_kline) k USING(code) WHERE k.code IS NULL;"
  echo "== 行数分布 =="
  db_sql "SELECT COUNT(*) codes, MIN(cnt) min_rows, MAX(cnt) max_rows, ROUND(AVG(cnt),0) avg_rows FROM (SELECT code,COUNT(*) cnt FROM cn_stock_daily_kline GROUP BY code) t;"
  echo "== OHLC 空值(应0) =="
  db_sql "SELECT COUNT(*) null_ohlc FROM cn_stock_daily_kline WHERE open IS NULL OR close IS NULL OR high IS NULL OR low IS NULL;"
  echo "== 抽样蓝筹 =="
  db_sql "SELECT code,name,COUNT(*) cnt,MIN(date) first_d,MAX(date) last_d FROM cn_stock_daily_kline WHERE code IN ('600519','000001','300750','601398') GROUP BY code,name;"
}

cmd_kline_status(){
  hr; echo "[进程]"; docker top "$APP" | grep kline_history_loader || echo "loader 已结束"
  hr; echo "[断点文件]"; wc -l "$CACHE_HOST/kline_done.txt" "$CACHE_HOST/kline_failed.txt" 2>/dev/null
  hr; echo "[表覆盖]"; db_sql "SELECT COUNT(*) rows_cnt,COUNT(DISTINCT code) codes,MIN(date) mn,MAX(date) mx FROM cn_stock_daily_kline; SELECT adjust,COUNT(*) AS rows_cnt FROM cn_stock_daily_kline GROUP BY adjust;"
  hr; echo "[失败清单(空=无)]"; head -20 "$CACHE_HOST/kline_failed.txt" 2>/dev/null || echo none
}

cmd_kline_log(){ local n=${2:-40}; echo "== kline_history.log =="; tail -n "$n" "$CACHE_HOST/kline_history.log" 2>/dev/null; echo "== kline_progress.txt =="; tail -n "$n" "$CACHE_HOST/kline_progress.txt" 2>/dev/null; }

cmd_logs_docker(){ local n=${2:-120}; docker logs --tail="$n" "$APP"; }
cmd_logs_app(){
  docker exec "$APP" sh -c 'echo "== execute_job =="; tail -n 80 /data/InStock/instock/log/stock_execute_job.log 2>/dev/null || echo none; echo "== web =="; tail -n 40 /data/InStock/instock/log/stock_web.log 2>/dev/null || echo none'
}

cmd_kline_run(){
  local start=${2:-20210101}; local workers=${3:-10}
  docker exec -d "$APP" sh -c "cd $APP_DIR && PYTHONPATH=$APP_DIR KLINE_START=$start KLINE_WORKERS=$workers python3 $KLINE_PY >> instock/cache/kline_history.log 2>&1"
  echo "started: start=$start workers=$workers; 用 kline-status 查看"
}
cmd_kline_stop(){
  for p in $(docker top "$APP" 2>/dev/null | grep kline_history_loader | awk '{print $2}'); do kill "$p" 2>/dev/null && echo "killed $p"; done
}

cmd_backup_now(){ bash "$COMPOSE_DIR/backup_db.sh"; }
cmd_backup_list(){ ls -lh "$COMPOSE_DIR"/backup/*.sql.gz 2>/dev/null; }
cmd_backup_restore(){
  if [ "$2" = "--confirm" ]; then local f="$3"; else local f="$2"; local confirm="$2"; fi
  if [ "$2" != "--confirm" ]; then
    echo "DRY-RUN(未执行). 真正恢复将执行:"
    echo "  gunzip -c $f | docker exec -i $DB sh -c 'mariadb -u$DB_USER -p$DB_PASS $DB_NAME'"
    echo "确认无误后执行: bash $0 backup-restore --confirm $f"
    return
  fi
  [ -z "$f" ] && { echo "用法: backup-restore --confirm <file.gz>"; return; }
  echo "!! 将用 $f 覆盖库 $DB_NAME ; 5 秒后开始, Ctrl-C 取消"; sleep 5
  gunzip -c "$f" | docker exec -i "$DB" sh -c "mariadb -u$DB_USER -p$DB_PASS $DB_NAME" && echo RESTORE_OK || echo RESTORE_FAIL
}

cmd_restart_app(){ docker restart "$APP"; }
cmd_restart_db(){ docker restart "$DB"; }
cmd_restart_all(){ docker compose -f "$COMPOSE_DIR/docker-compose.yml" restart; }
cmd_cache_list(){ docker exec "$APP" sh -c 'du -sh /data/InStock/instock/cache/hist 2>/dev/null; find /data/InStock/instock/cache/hist -type f | wc -l'; }
cmd_cache_clear(){ docker exec "$APP" sh -c 'rm -rf /data/InStock/instock/cache/hist/* && echo "hist cache cleared"; true'; }

cmd_health(){
  cmd_status; hr; echo "[核心表]"; cmd_counts; hr; echo "[历史质量摘要]"; cmd_verify; hr
  echo "[备份最新]"; cmd_backup_list
}

case "${1:-help}" in
  status) cmd_status;;
  health) cmd_health;;
  tables) cmd_tables;;
  counts) cmd_counts;;
  verify) cmd_verify;;
  kline-status) cmd_kline_status;;
  kline-log) cmd_kline_log "$@";;
  logs-docker) cmd_logs_docker "$@";;
  logs-app) cmd_logs_app;;
  backup-list) cmd_backup_list;;
  cache-list) cmd_cache_list;;
  enter) docker exec -it "$APP" sh;;
  db) docker exec -it "$DB" mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME";;
  sql) shift; db_sql "$*";;
  job-basic) docker exec "$APP" python3 "$JOB_DIR/basic_data_daily_job.py";;
  job-close) docker exec "$APP" python3 "$JOB_DIR/execute_daily_job.py";;
  job-afterclose) docker exec "$APP" python3 "$JOB_DIR/basic_data_after_close_daily_job.py";;
  job-run) shift; py="$1"; shift; docker exec "$APP" python3 "$JOB_DIR/$py" "$@";;
  kline-run) cmd_kline_run "$@";;
  kline-stop) cmd_kline_stop;;
  backup-now) cmd_backup_now;;
  backup-restore) cmd_backup_restore "$@";;
  restart-app) cmd_restart_app;;
  restart-db) cmd_restart_db;;
  restart-all) cmd_restart_all;;
  cache-clear) cmd_cache_clear;;
  help|--help|-h) usage;;
  *) echo "未知子命令: $1"; usage; exit 1;;
esac
