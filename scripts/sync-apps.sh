#!/bin/bash
# ============================================================
# 同步应用文件到 1Panel 本地应用目录
# ------------------------------------------------------------
# 只负责落盘，不调用 1Panel API；需要同步后自动刷新列表时用
# scripts/sync-and-refresh.sh。
#
# 变量（未设置时使用 scripts/check-env.sh 里的默认值）：
#   PANEL_ROOT     1Panel 安装根目录，默认 /opt/1panel
#   GIT_REPO       应用仓库地址，默认 https://github.com/willow-god/appstore
#   APPS           要同步的应用（逗号或空格分隔），留空表示全部
#   KEEP_VERSIONS  每个应用保留的历史版本目录数量，默认 10
#
# 示例：
#   bash scripts/sync-apps.sh
#   APPS="whoami,ech0" bash scripts/sync-apps.sh
#
# 版本目录策略：仓库里存在的版本每次覆盖更新，仓库里已经没有的旧版本
# 继续保留（最多 KEEP_VERSIONS 个）。1Panel 本地应用同步会删除本地已不
# 存在的版本对应的 app_details 记录，而 app_installs.app_detail_id 仍指
# 着它，删掉目录就会让已安装应用的详情页和升级报 JSON 错误。保留历史
# 目录是避免这个问题最不侵入的办法。
# ============================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=check-env.sh
. "$SCRIPT_DIR/check-env.sh" sync-apps

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR"
    fi
}
trap cleanup EXIT

# ---------- 1. 克隆仓库 ----------
echo "📥 Cloning appstore repo..."
rm -rf -- "$TMP_DIR"
mkdir -p "$(dirname "$TMP_DIR")"
git clone --depth 1 "$GIT_REPO" "$TMP_DIR"

# ---------- 2. 镜像替换 + 适配脚本 ----------
echo "🔄 Mirroring apps..."
if [ -f "$TMP_DIR/scripts/mirror.sh" ]; then
    bash "$TMP_DIR/scripts/mirror.sh"
else
    echo "⚠️ scripts/mirror.sh 不存在，跳过镜像替换"
fi

# ---------- 3. 应用列表 ----------
app_list=()
if [ -n "${APPS:-}" ]; then
    IFS=', ' read -r -a app_list <<<"$APPS"
else
    for app_path in "$TMP_DIR/apps/"*/; do
        [ -d "$app_path" ] && app_list+=("$(basename "$app_path")")
    done
fi

if [ "${#app_list[@]}" -eq 0 ]; then
    echo "❌ 没有可同步的应用"
    exit 1
fi

mkdir -p "$LOCAL_APPS_DIR"

# ---------- 4. 复制应用 ----------
# 只保留最近的 KEEP_VERSIONS 个版本目录；仍在仓库中的版本不清理
prune_versions() {
    local app_name="$1" src="$2" dst="$3"
    local -a versions=()
    local version

    while IFS= read -r version; do
        [ -n "$version" ] && versions+=("$version")
    done < <(find "$dst" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | sort -V)

    local total=${#versions[@]}
    [ "$total" -le "$KEEP_VERSIONS" ] && return 0

    local remove=$((total - KEEP_VERSIONS))
    local i
    for ((i = 0; i < remove; i++)); do
        version="${versions[$i]}"
        if [ -d "$src/$version" ]; then
            echo "ℹ️  $app_name/$version 仍在仓库中，跳过清理"
            continue
        fi
        rm -rf -- "$dst/$version"
        echo "🧹 $app_name: 清理历史版本 $version（保留最近 $KEEP_VERSIONS 个）"
    done
}

sync_app() {
    local app_name="$1"
    local src="$TMP_DIR/apps/$app_name"
    local dst="$LOCAL_APPS_DIR/$app_name"
    local version_dir version

    if [ ! -d "$src" ]; then
        echo "❌ 仓库中没有应用 $app_name，跳过"
        return 1
    fi

    echo "🔁 Updating app: $app_name"
    mkdir -p "$dst"

    # 应用级文件（data.yml、logo.png、README.md 等）直接覆盖
    find "$src" -mindepth 1 -maxdepth 1 -type f -exec cp -f {} "$dst/" \;

    # 仓库里存在的版本目录覆盖更新，不碰其他历史版本
    for version_dir in "$src"/*/; do
        [ -d "$version_dir" ] || continue
        version="$(basename "$version_dir")"
        rm -rf -- "$dst/$version"
        cp -r "$version_dir" "$dst/$version"
    done

    prune_versions "$app_name" "$src" "$dst"
}

failed=()
for app_name in "${app_list[@]}"; do
    [ -n "$app_name" ] || continue
    sync_app "$app_name" || failed+=("$app_name")
done

echo "✅ Local app files updated: $LOCAL_APPS_DIR"

if [ "${#failed[@]}" -gt 0 ]; then
    echo "⚠️ 以下应用未同步: ${failed[*]}"
    exit 1
fi
