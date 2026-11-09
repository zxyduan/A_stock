#!/bin/sh
# 文档补采: 生效compose/备份工具/Web标题/重启策略
set +e
echo "=== compose yml on server ==="
cat /data/instock/docker-compose.yml
echo "=== dump binary in DB container ==="
docker exec InStockDbService sh -c 'command -v mariadb-dump || command -v mysqldump || echo no-dump-tool'
echo "=== web title ==="
curl -sS -m8 http://127.0.0.1:9988/instock/ 2>/dev/null | grep -o '<title>[^<]*</title>' | head -1
echo "=== restart policy ==="
docker inspect InStock --format 'app: restart={{.HostConfig.RestartPolicy.Name}} image={{.Config.Image}}'
docker inspect InStockDbService --format 'db:  restart={{.HostConfig.RestartPolicy.Name}}'
echo "=== supervisorctl available? ==="
docker exec InStock sh -c 'command -v supervisorctl || echo no-supervisorctl'
echo FACTS_DONE
