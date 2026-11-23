#!/bin/bash
# ============================================================
# 按 PRUNE_APPS 删除 1Panel 本地应用目录里已下线的应用
# ------------------------------------------------------------
# scripts/mirror.sh 会按文件名顺序执行 adapters/ 下的每个 .sh，本脚本
# 也可以单独执行：
#   bash adapters/prune-apps.sh
#   PRUNE_APPS="旧应用1,旧应用2" bash adapters/prune-apps.sh
#   PRUNE_APPS=... LOCAL_APPS_DIR=/opt/1panel/resource/apps/local bash adapters/prune-apps.sh
#
# 只删除 $LOCAL_APPS_DIR/<应用名> 这份已部署的应用目录，用来清理上游已经
# 下线、但服务器上一直留着的应用（同步脚本只复制、从不删除）。不卸载已安
# 装实例，也不动其他应用。
#
# 删除保护：
#   - 只认 PRUNE_APPS 里明确写出的名字
#   - 该应用仍在仓库 apps/ 里时跳过（下个同步周期又会被复制回来）
#   - 该应用在 1Panel 里还有已安装实例时跳过：删掉商店定义会让已安装应用的
#     详情、参数和升级信息失去依据
#   - 无法确认是否已安装（没有 sqlite3、数据库不存在或被占用）时也跳过，
#     宁可留下旧定义，也不动可能有实例在用的应用
#   - 目标是普通目录且含 data.yml，符号链接不删
#   - LOCAL_APPS_DIR 未显式传参时，由脚本位置推导，且上级目录必须叫 local，
#     避免在普通开发检出里误删兄弟目录
#
# 数据库只读打开（-readonly + PRAGMA query_only），只做 SELECT，不写入。
# 幂等：没有要删的内容时静默通过。
# 退出码：0 完成（含跳过）；非零只有 rm 之外的环境问题
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRUNE_VAR="PRUNE_APPS"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

# 1Panel 本地应用目录：优先用显式传入的，其次由 PANEL_ROOT 拼出，
# 都没有时按脚本位置推导（脚本在 <local>/<应用>/ 里）
if [[ -n "${LOCAL_APPS_DIR:-}" ]]; then
    DEPLOYED_DIR_EXPLICIT=1
elif [[ -n "${PANEL_ROOT:-}" ]]; then
    LOCAL_APPS_DIR="$PANEL_ROOT/resource/apps/local"
    DEPLOYED_DIR_EXPLICIT=1
else
    LOCAL_APPS_DIR="$(dirname "$ROOT_DIR")"
    DEPLOYED_DIR_EXPLICIT=0
fi

# ---------- 读取 PRUNE_APPS ----------
prune_raw="${PRUNE_APPS:-}"
if [[ -z "$prune_raw" ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "⚠️  未找到 $ENV_FILE，跳过已部署副本清理"
        exit 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^${PRUNE_VAR}=\"?([^\"]*)\"?$ ]]; then
            prune_raw="${BASH_REMATCH[1]}"
            break
        fi
    done <"$ENV_FILE"
fi

prune_items=()
IFS=',' read -r -a raw_items <<<"$prune_raw"
for item in ${raw_items[@]+"${raw_items[@]}"}; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    item="${item%$'\r'}"
    [[ -z "$item" ]] && continue
    prune_items+=("$item")
done

if [[ "${#prune_items[@]}" -eq 0 ]]; then
    echo "✅ $PRUNE_VAR 为空，无需清理"
    exit 0
fi

# ---------- 删除已部署的本地应用副本 ----------
if [[ $DEPLOYED_DIR_EXPLICIT -eq 0 && "$(basename "$LOCAL_APPS_DIR")" != "local" ]]; then
    # 脚本不在 1Panel 本地应用目录里（比如普通的开发检出），不做任何删除
    echo "ℹ️  $LOCAL_APPS_DIR 不是 1Panel 本地应用目录，跳过已部署副本清理"
    exit 0
fi

# ---------- 1Panel 数据库（只读） ----------
# app_installs 里存在该应用的记录，就说明商店定义还在被一个已安装实例使用。
PANEL_DB="${PANEL_DB:-}"
if [[ -z "$PANEL_DB" ]]; then
    if [[ -n "${PANEL_ROOT:-}" ]]; then
        PANEL_DB="$PANEL_ROOT/db/agent.db"
    elif [[ -n "$LOCAL_APPS_DIR" && "$(basename "$LOCAL_APPS_DIR")" == "local" ]]; then
        PANEL_DB="$(cd "$LOCAL_APPS_DIR/../.." && pwd)/db/agent.db"
    fi
fi

DB_STATE="unavailable"
DB_REASON="未找到 1Panel 数据库路径"

init_installed_db() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        DB_REASON="未找到 sqlite3 命令"
        return
    fi
    if [[ -z "$PANEL_DB" || ! -f "$PANEL_DB" ]]; then
        DB_REASON="数据库不存在: ${PANEL_DB:-<未推导出>}"
        return
    fi
    if ! sqlite3 -readonly -batch "$PANEL_DB" "PRAGMA query_only=ON; SELECT 1;" >/dev/null 2>&1; then
        DB_REASON="数据库只读打开失败（被占用或权限不足）: $PANEL_DB"
        return
    fi
    DB_STATE="ready"
}

# 只读查询；失败时返回非零，调用方按「无法确认」处理
sqlite_ro() {
    sqlite3 -readonly -batch -noheader -cmd "PRAGMA query_only=ON;" "$PANEL_DB" "$1" 2>/dev/null
}

# 设置 INSTALL_STATE（none | installed | unknown）与 INSTALL_INFO。
# 1Panel 本地应用的 key 是 "local" + 应用目录名。
check_installed() {
    local app_name="$1" key app_id row count names

    INSTALL_STATE="unknown"
    INSTALL_INFO="$DB_REASON"

    [[ "$DB_STATE" == "ready" ]] || return 0

    key="local$app_name"
    key="${key//\'/\'\'}"
    if ! app_id="$(sqlite_ro "SELECT id FROM apps WHERE resource='local' AND key='$key' LIMIT 1;")"; then
        INSTALL_INFO="数据库查询失败"
        return 0
    fi
    if [[ -z "$app_id" ]]; then
        INSTALL_STATE="none"
        INSTALL_INFO="1Panel 中没有该应用记录"
        return 0
    fi

    if ! row="$(sqlite_ro "SELECT count(*) || '|' || COALESCE(group_concat(i.name || ' (' || COALESCE(d.version, '?') || ')', ', '), '') FROM app_installs i LEFT JOIN app_details d ON d.id = i.app_detail_id WHERE i.app_id=$app_id;")"; then
        INSTALL_INFO="数据库查询失败"
        return 0
    fi
    count="${row%%|*}"
    names="${row#*|}"
    if [[ -z "$count" || "$count" == "0" ]]; then
        INSTALL_STATE="none"
        INSTALL_INFO="没有已安装实例"
        return 0
    fi
    INSTALL_STATE="installed"
    INSTALL_INFO="$count 个已安装实例${names:+：$names}"
}

init_installed_db

deployed_hit=0
skipped_hit=0
for item in "${prune_items[@]}"; do
    target="$LOCAL_APPS_DIR/$item"

    # 目录不在就是已经清理过，保持安静（幂等）
    [[ -e "$target" ]] || continue

    if [[ -d "$ROOT_DIR/apps/$item" ]]; then
        echo "⚠️  应用 $item 仍在本仓库 apps/ 中，跳过删除已部署副本: $target"
        continue
    fi

    if [[ -L "$target" || ! -d "$target" ]]; then
        echo "⚠️  $target 不是普通目录，跳过删除"
        continue
    fi

    if [[ ! -f "$target/data.yml" ]]; then
        echo "⚠️  $target 缺少 data.yml，不是 1Panel 应用目录，跳过删除"
        continue
    fi

    check_installed "$item"
    case "$INSTALL_STATE" in
        installed)
            echo "🛡️  应用 $item 仍有 $INSTALL_INFO，保留应用定义: $target"
            skipped_hit=$((skipped_hit + 1))
            continue
            ;;
        unknown)
            echo "⚠️  无法确认 $item 是否已安装（$INSTALL_INFO），保守跳过删除: $target"
            skipped_hit=$((skipped_hit + 1))
            continue
            ;;
    esac

    if rm -rf -- "$target"; then
        echo "🗑️  已删除已部署应用: $target"
        deployed_hit=1
    else
        # 删不掉不该阻断整轮同步，留个提示让维护者手动处理
        echo "⚠️  删除失败，请手动清理: $target"
    fi
done

if [[ $deployed_hit -eq 0 ]]; then
    if [[ $skipped_hit -eq 0 ]]; then
        echo "✅ 已部署应用目录无需清理（$PRUNE_VAR 中的应用不在 $LOCAL_APPS_DIR 中）"
    else
        echo "✅ 已部署应用目录无需清理（有 $skipped_hit 个应用因已安装或无法确认而保留）"
    fi
fi
