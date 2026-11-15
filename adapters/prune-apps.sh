#!/bin/bash
# ============================================================
# 按 PRUNE_APPS 清理应用
# ------------------------------------------------------------
# mirror.sh 执行镜像替换前会运行 adapters/ 下的所有 .sh 脚本。
# 本脚本读取 .env 里的 PRUNE_APPS（逗号分隔的应用名），做两件事：
#
#   1. 从 .env 的 *_LIST / *_ARRAY 应用清单中移除这些名字
#      —— 决定 mirror.sh 是否还会给它们做镜像替换
#   2. 删除 1Panel 本地应用目录里已经拷贝过去的同名应用
#      —— 同步脚本只负责复制，上游删掉的应用不会自己消失
#
# 为什么不按 apps/ 目录是否存在来判断清单：用户的清单里可能有来自其他
# 应用商店的应用，本仓库里没有对应目录并不代表它是失效条目。
#
# 删除已部署副本只认 PRUNE_APPS 里明确写出的名字，并且要求：
#   - 目标是 1Panel 应用目录（含 data.yml）的普通目录，不是符号链接
#   - 该应用已经不在本仓库 apps/ 里（否则复制回来也没意义，直接跳过）
#   - 目录由克隆位置推导时（LOCAL_APPS_DIR 未显式传入），克隆目录的上级
#     必须叫 local，避免在普通开发检出里误删兄弟目录
#
# - 幂等：没有可清理的内容时不写文件、不报错
# - 通用：任何以 _LIST / _ARRAY 结尾的键都会被处理
# - 保留原换行风格（LF / CRLF）
# - 可单独运行：bash adapters/prune-apps.sh
#   也可用 ENV_FILE=... 指向其他 .env，或用 PRUNE_APPS=... 直接传入清单，
#   用 LOCAL_APPS_DIR=... 指定要清理的 1Panel 本地应用目录
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
# 清理清单的变量名。故意不以 _LIST 结尾，避免被当成待清理的清单处理
PRUNE_VAR="PRUNE_APPS"

# 1Panel 本地应用目录：同步脚本默认把应用复制到克隆目录的上一级
if [[ -n "${LOCAL_APPS_DIR:-}" ]]; then
    DEPLOYED_DIR_EXPLICIT=1
else
    LOCAL_APPS_DIR="$(dirname "$ROOT_DIR")"
    DEPLOYED_DIR_EXPLICIT=0
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "⚠️  未找到 $ENV_FILE，跳过应用清单清理"
    exit 0
fi

# ---------- 读取 PRUNE_APPS ----------
# 优先用环境变量传入的值，否则从 .env 里解析
prune_raw="${PRUNE_APPS:-}"
if [[ -z "$prune_raw" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^${PRUNE_VAR}=\"?([^\"]*)\"?$ ]]; then
            prune_raw="${BASH_REMATCH[1]}"
            break
        fi
    done <"$ENV_FILE"
fi

# 规整成 ,a,b,c, 形式，方便整词匹配
prune_set=","
prune_items=()
IFS=',' read -r -a raw_items <<<"$prune_raw"
for item in ${raw_items[@]+"${raw_items[@]}"}; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    item="${item%$'\r'}"
    [[ -z "$item" ]] && continue
    prune_items+=("$item")
    prune_set="${prune_set}${item},"
done

if [[ "$prune_set" == "," ]]; then
    echo "✅ $PRUNE_VAR 为空，无需清理应用清单"
    exit 0
fi

# ---------- 1. 逐行改写 .env 中的应用清单 ----------
# 保留原文件的换行风格：Git 仓库里是 LF，Windows 检出后可能是 CRLF
if [[ "$(head -c 8192 "$ENV_FILE")" == *$'\r'* ]]; then
    EOL=$'\r\n'
else
    EOL=$'\n'
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

emit() { printf '%s%s' "$1" "$EOL" >>"$TMP_FILE"; }

changed=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"

    # 匹配 KEY="a,b,c" / KEY=a,b,c，且 KEY 以 _LIST 或 _ARRAY 结尾
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*(_LIST|_ARRAY))=\"?([^\"]*)\"?$ ]]; then
        key="${BASH_REMATCH[1]}"
        raw_value="${BASH_REMATCH[3]}"

        kept=()
        dropped=()

        IFS=',' read -r -a items <<<"$raw_value"
        for item in ${items[@]+"${items[@]}"}; do
            # 去掉首尾空白
            item="${item#"${item%%[![:space:]]*}"}"
            item="${item%"${item##*[![:space:]]}"}"
            [[ -z "$item" ]] && continue

            if [[ "$prune_set" == *",$item,"* ]]; then
                dropped+=("$item")
            else
                kept+=("$item")
            fi
        done

        if [[ ${#dropped[@]} -gt 0 ]]; then
            new_value=""
            for item in ${kept[@]+"${kept[@]}"}; do
                new_value="${new_value:+$new_value,}$item"
            done
            emit "${key}=\"${new_value}\""
            echo "🧹 $key: 按 $PRUNE_VAR 移除 -> ${dropped[*]}"
            changed=1
        else
            # 没有命中就不动这一行，保持文件原样
            emit "$line"
        fi
    else
        emit "$line"
    fi
done <"$ENV_FILE"

if [[ $changed -eq 1 ]]; then
    cat "$TMP_FILE" >"$ENV_FILE"
    echo "✅ 应用清单已更新: $ENV_FILE"
else
    echo "✅ 应用清单无需清理（$PRUNE_VAR 中的名字都不在任何清单里）"
fi

# ---------- 2. 删除已部署的本地应用副本 ----------
# 同步脚本会把 apps/ 下的目录复制到 1Panel 本地应用目录，但从不删除上游
# 已经下线（或从未同步过）的应用。这里按同一份 PRUNE_APPS 一并清理。
deployed_hit=0
deployed_dir_usable=1

if [[ $DEPLOYED_DIR_EXPLICIT -eq 0 && "$(basename "$LOCAL_APPS_DIR")" != "local" ]]; then
    # 克隆目录不在 1Panel 本地应用目录里（比如普通的开发检出），不做任何删除
    deployed_dir_usable=0
    echo "ℹ️  $LOCAL_APPS_DIR 不是 1Panel 本地应用目录，跳过已部署副本清理"
fi

if [[ $deployed_dir_usable -eq 1 ]]; then
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

        if rm -rf -- "$target"; then
            echo "🗑️  已删除已部署应用: $target"
            deployed_hit=1
        else
            # 删不掉不该阻断整轮同步，留个提示让维护者手动处理
            echo "⚠️  删除失败，请手动清理: $target"
        fi
    done

    if [[ $deployed_hit -eq 0 ]]; then
        echo "✅ 已部署应用目录无需清理（$PRUNE_VAR 中的应用不在 $LOCAL_APPS_DIR 中）"
    fi
fi
