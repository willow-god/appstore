#!/bin/bash
# ============================================================
# 环境变量校验与默认值（由其他脚本 source，不单独执行）
# ------------------------------------------------------------
# 用法：
#   . "$SCRIPT_DIR/check-env.sh" <脚本名>
#
# 作用：
#   1. 按脚本名列出必填变量，缺任何一个就退出，调用方不会继续执行
#   2. 填好带默认值的变量，并统一推导目录，避免每个脚本各拼一份路径
#
# 变量全在这里定义，调用方只需要：
#   . "$SCRIPT_DIR/check-env.sh" sync-apps
#
# 退出码：0 就绪；2 脚本名不合法；3 缺少必填变量；4 变量取值不合法
# ============================================================

_check_env_script="${1:-}"
_check_env_allowed="mirror sync-apps refresh"

case "$_check_env_script" in
    "")
        echo "❌ check-env.sh 需要传入脚本名（可选: $_check_env_allowed）" >&2
        exit 2
        ;;
    mirror | sync-apps | refresh) ;;
    *)
        echo "❌ 未知脚本名: $_check_env_script（可选: $_check_env_allowed）" >&2
        exit 2
        ;;
esac

# ---------- 默认值 ----------
# 1Panel 安装根目录。其余目录都从这里推导，装在别处时只改这一个
: "${PANEL_ROOT:=/opt/1panel}"
# 应用仓库地址。国内可换成 https://cnb.cool/Liiiu/appstore
: "${GIT_REPO:=https://github.com/willow-god/appstore}"
# 每个应用在本机保留的历史版本目录数量（用于保护已安装应用的详情记录）
: "${KEEP_VERSIONS:=10}"

export PANEL_ROOT GIT_REPO KEEP_VERSIONS

# 本地应用目录（1Panel 应用商店资源）与临时克隆目录
export LOCAL_APPS_DIR="${LOCAL_APPS_DIR:-$PANEL_ROOT/resource/apps/local}"
export TMP_DIR="${TMP_DIR:-$LOCAL_APPS_DIR/tmp-appstore}"

# 1Panel 数据库：固定由 PANEL_ROOT 拼出，不开放覆盖（只读查询已安装版本）
PANEL_DB="$PANEL_ROOT/db/agent.db"
export PANEL_DB

# 1Panel API 配置（只有 refresh 需要）
export ONEPANEL_URL="${ONEPANEL_URL:-}"
export ONEPANEL_APIKEY="${ONEPANEL_APIKEY:-}"
export ONEPANEL_NODE="${ONEPANEL_NODE:-}"

# ---------- 必填校验 ----------
_missing=()
case "$_check_env_script" in
    refresh)
        [ -n "$ONEPANEL_URL" ] || _missing+=("ONEPANEL_URL")
        [ -n "$ONEPANEL_APIKEY" ] || _missing+=("ONEPANEL_APIKEY")
        ;;
esac

if [ "${#_missing[@]}" -gt 0 ]; then
    _missing_text=$(IFS=' '; echo "${_missing[*]}")
    echo "❌ 缺少必填环境变量: ${_missing_text}" >&2
    echo "   示例：" >&2
    echo "   ONEPANEL_URL=https://panel.example.com ONEPANEL_APIKEY=你的APIKey \\" >&2
    echo "   bash scripts/refresh.sh" >&2
    exit 3
fi

# ---------- 取值校验 ----------
if ! [[ "$KEEP_VERSIONS" =~ ^[0-9]+$ ]] || [ "$KEEP_VERSIONS" -lt 1 ]; then
    echo "❌ KEEP_VERSIONS 必须是正整数，当前值: $KEEP_VERSIONS" >&2
    exit 4
fi

if [ "$_check_env_script" = "refresh" ] && [ -z "$PANEL_ROOT" ]; then
    echo "❌ PANEL_ROOT 不能为空" >&2
    exit 4
fi

unset _check_env_script _check_env_allowed _missing _missing_text
