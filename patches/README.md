# 运行时补丁层（compose 只读挂载，不重建镜像）

原则：镜像内文件不直接改；本地差异由 `docker-compose.yml` 的 `volumes` 以 `:ro` 挂载覆盖。
回滚：删除对应挂载行后 `docker compose -f /data/instock/docker-compose.yml restart instock`。

| 补丁文件（仓内） | 挂载到容器内路径 | 修复问题 | 状态 |
|---|---|---|---|
| `eastmoney_fetcher.py` | `/data/InStock/instock/core/eastmoney_fetcher.py:ro` | 镜像未装 brotli，东财 br/zstd 编码返回导致长字段 `r.json()` 报错；请求头降级为 `gzip,deflate` | 已生效，与容器内文件 md5 一致 |

待落地（路线B / 安全项，尚未提交）：
- `stockfetch.py` 2 处、`calculate_indicator.py` 79 处、策略 6 文件 7 处的 pandas CoW 就地写替换；
- `web_service.py` 的 `debug / xsrf / cookie_secret` 安全项。

落地后必须在上表登记挂载点，并在 `docker-compose.yml` 增加只读挂载行。
