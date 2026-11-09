# InStock 部署与本地补丁仓库

## 1. 仓库定位
本仓库只版本化在官方上游基础上的部署改造、本地补丁与运维脚本；不入库上游源码全量快照、数据库与运行日志。
- 上游项目: myhhub/stock（InStock 股票系统，GitHub）
- 远程仓库: git@github.com:zxyduan/A_stock.git（建议设为 Private）
- 运行镜像: mayanghua/instock:latest，2026-11-08 本机重建，镜像 ID 16f0ce69802
- 容器: InStock（应用，宿主机端口 9988）、InStockDbService（MariaDB）
- 编排: docker-compose.yml（持久化卷、healthcheck、restart always、只读补丁挂载）

## 2. 关键自定义清单
- patches/eastmoney_fetcher.py：只读挂载覆盖镜像内同名文件，去掉 br、zstd 解压头要求，修复东财接口 Content-Encoding br 无法解码导致 r.json 报错的问题。
- build/Dockerfile、build/Dockerfile.new：本机重建镜像所用 Dockerfile；Dockerfile.bak-orig 为上游原始备份。
- patch_*、verify_*、probe_*、diag_*、poll_*、restart_*、run_basic.sh、ops.sh、morning_check.sh、quality_check.sh、final_health.sh：补丁生成、验证与日常运维脚本。
- init_schema.sql：数据库初始化补充结构。
- 数据库连接见 docker-compose.yml，账号密码仅在 instock-net 内网桥接内使用，不要把 3306 暴露到公网。

## 3. 不入库内容（.gitignore）
- mariadb/data：约 1.3G 数据库数据文件，由 backup_db.sh 导出到 backup 目录。
- backup：历史 sql.gz 备份与备份日志；备份文件需另行异地保存，不进 Git。
- app/cache、app/log：运行缓存与应用日志。
- 全部 *.log：构建、排障、探针输出日志。
- eastmoney_cookie.txt、proxy.txt：Cookie 与代理凭据，手工维护，禁止入库。
- build/stock、src/stock-master：上游 zip 解压只读副本（约 12M、13M，内容未改动），避免与上游重复占库。
- __pycache__、*.pyc：Python 缓存。

## 4. 恢复与重建步骤
1. 安装 Docker 与 docker compose 插件。
2. 准备镜像：mariadb:latest；应用镜像可拉取 mayanghua/instock:latest，或按 build/Dockerfile 本机重建。
3. 克隆本仓库到 /data/instock，按 docker-compose.yml 的卷挂载点创建空目录 mariadb/data、app/cache、app/log。
4. 手工创建 eastmoney_cookie.txt、proxy.txt（不入库），按需填 Cookie 与代理。
5. 数据库恢复：将历史 sql.gz 放入 backup 目录，按 backup_db.sh 中的恢复逻辑导入 instockdb。
6. 在 /data/instock 执行 docker compose up -d；等待 InStockDbService healthy，InStock 自动启动。
7. 补丁由 compose 只读 volume 自动挂载生效；修改 patches/eastmoney_fetcher.py 后执行 docker restart InStock。

## 5. 日常提交流程
cd /data/instock
git add -A
git commit -m "说明本次改动"
git push origin main

## 6. 边界与注意
- 本仓库不是上游源码 fork，不跟踪上游提交历史；上游升级优先更换镜像 tag 并回归验证补丁兼容性，不要直接覆盖补丁文件。
- 若后续需要完整跟踪上游源码，另行 fork myhhub/stock 并把本仓库补丁作为独立层叠加。
