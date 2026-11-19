#!/bin/bash
# ============================================================
# 镜像源替换（只做这一件事，直接在已部署的 1Panel 应用目录上改）
# ------------------------------------------------------------
# 用法（在 scripts/sync-apps.sh 之后执行，顺序反了改的是上一次的内容）：
#   bash scripts/mirror.sh
#
#   # 换镜像加速配置
#   MIRROR_CONFIG=/opt/mirror-config.env bash scripts/mirror.sh
#
# 作用：
#   1. 依次执行 adapters/*.sh（应用级适配，如按 PRUNE_APPS 删除已下线应用）
#   2. 按仓库根目录 .env 的应用清单，把
#      $LOCAL_APPS_DIR/<应用>/<版本>/docker-compose.yml 里的镜像仓库前缀
#      替换成配置文件里的加速地址
#
# 说明：
#   - 幂等：重复执行不会二次替换，也不留备份文件
#   - 只改已部署目录，不改仓库克隆；每次 sync-apps.sh 覆盖回去后要重新执行
#
# 变量：
#   PANEL_ROOT     1Panel 安装根目录，默认 /opt/1panel（LOCAL_APPS_DIR 由它拼出）
#   MIRROR_CONFIG  镜像加速配置文件，默认 /opt/mirror-config.env
#   ENV_FILE       应用清单文件，默认仓库根目录 .env
#
# 退出码：0 完成（配置缺失时跳过替换）；1 .env 不存在；2/4 check-env 拒绝
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=check-env.sh
. "$SCRIPT_DIR/check-env.sh" mirror

MIRROR_CONFIG="${MIRROR_CONFIG:-/opt/mirror-config.env}"

# ---------- 1. 执行 adapters 目录下的所有 .sh ----------
# 不管镜像配置文件是否存在都执行，避免缺配置时适配脚本被跳过
ADAPTERS_DIR="$ROOT_DIR/adapters"

if [ -d "$ADAPTERS_DIR" ]; then
    for script in "$ADAPTERS_DIR"/*.sh; do
        [ -f "$script" ] || { echo "目录 $ADAPTERS_DIR 下没有找到 .sh 文件"; break; }
        echo "执行 adapters 脚本: $script"
        chmod +x "$script"
        "$script"
    done
else
    echo "目录不存在: $ADAPTERS_DIR，跳过 adapters 脚本执行"
fi

# ---------- 2. 镜像替换 ----------
if [[ ! -f "$MIRROR_CONFIG" ]]; then
    echo "镜像配置文件不存在: $MIRROR_CONFIG，跳过镜像替换"
    exit 0
fi

set -a
# shellcheck disable=SC1090
source "$MIRROR_CONFIG"
set +a

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env 文件不存在: $ENV_FILE"
    exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

replace_image() {
    local file="$1"
    local src_registry="$2"
    local target_registry="$3"

    # 已经替换过的文件不会再有源前缀，直接跳过（幂等，也不产生备份文件）
    grep -qE "\b${src_registry}/" "$file" || return 0
    sed -i -E "s#\b${src_registry}/#${target_registry}/#g" "$file"
    echo "已替换 $file: $src_registry -> $target_registry"
}

if [[ ! -d "$LOCAL_APPS_DIR" ]]; then
    echo "本地应用目录不存在: $LOCAL_APPS_DIR，跳过镜像替换"
    exit 0
fi

# 每个源可以对应多个清单变量（空格分隔），指向的清单都会处理
declare -A SOURCES
SOURCES=(
    ["GHCR"]="GHCR_ENABLE GHCR_MIRROR ghcr.io GHCR_IO_LIST"
    ["QUAY"]="QUAY_ENABLE QUAY_MIRROR quay.io QUAY_IO_LIST"
    ["GCR"]="GCR_ENABLE GCR_MIRROR gcr.io GCR_IO_LIST"
    ["K8S_GCR"]="K8S_GCR_ENABLE K8S_GCR_MIRROR k8s.gcr.io K8S_GCR_IO_LIST"
    ["K8S_REG"]="K8S_REG_ENABLE K8S_REG_MIRROR registry.k8s.io REGISTRY_K8S_IO_LIST NON_DOCKER_IO_LIST"
)

for key in "${!SOURCES[@]}"; do
    read -r ENABLE_VAR MIRROR_VAR SRC_REG ARRAY_NAMES <<<"${SOURCES[$key]}"

    ENABLE=${!ENABLE_VAR}
    MIRROR=${!MIRROR_VAR}

    [[ "$ENABLE" != "true" ]] && continue

    for ARRAY_NAME in $ARRAY_NAMES; do
        APP_LIST=${!ARRAY_NAME:-}
        IFS=',' read -r -a APPS <<<"$APP_LIST"

        for app in "${APPS[@]}"; do
            # 清单为空或有多余逗号时会解析出空名字，跳过以免误扫整个目录
            [ -z "$app" ] && continue

            app_dir="$LOCAL_APPS_DIR/$app"
            if [ ! -d "$app_dir" ]; then
                echo "应用目录不存在，跳过: $app_dir"
                continue
            fi

            files=$(find "$app_dir" -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \))
            for file in $files; do
                replace_image "$file" "$SRC_REG" "$MIRROR"
            done
        done
    done
done

echo "镜像替换完成。"
