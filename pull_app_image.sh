#!/usr/bin/env bash
# 逐个镜像站显式拉取 mayanghua/instock:latest，成功后 retag 为标准镜像名
# 背景：docker daemon 默认轮询镜像站时，某站返回“不在白名单”会直接终止、不会自动切换下一站，
# 因此这里显式逐站尝试。
set +e
TARGET="mayanghua/instock:latest"
REGISTRIES=(
  "0vmzj3q6.mirror.aliyuncs.com"
  "vlgh0kqj.mirror.aliyuncs.com"
  "mirror.baidubce.com"
  "dockerproxy.com"
  "mirror.iscas.ac.cn"
  "huecker.io"
  "dockerhub.timeweb.cloud"
  "noohub.ru"
)
for reg in "${REGISTRIES[@]}"; do
  echo "===== TRY $reg ====="
  if docker pull "$reg/mayanghua/instock:latest"; then
    docker tag "$reg/mayanghua/instock:latest" "$TARGET"
    echo "===== APP_IMAGE_OK via $reg ====="
    docker images mayanghua/instock
    exit 0
  fi
done
echo "===== ALL_REGISTRY_FAILED ====="
exit 1
