#!/bin/bash
# ============================================================
# 刷新 1Panel 本地应用商店列表（只做这一件事）
# ------------------------------------------------------------
# 只调用 1Panel API（POST /api/v2/apps/sync/local）让面板重新扫描本地
# 应用目录，不复制文件、不执行其他脚本。应用文件请先由
# scripts/sync-apps.sh 落盘，镜像替换由 scripts/mirror.sh 完成。
#
# 用法：
#   ONEPANEL_URL=https://panel.example.com \
#   ONEPANEL_APIKEY=你的APIKey \
#   bash scripts/refresh.sh
#
#   # 从节点
#   ONEPANEL_URL=... ONEPANEL_APIKEY=... ONEPANEL_NODE=节点名 \
#   bash scripts/refresh.sh
#
# 变量：
#   ONEPANEL_URL     面板地址，可省略 http(s)://（必填）
#   ONEPANEL_APIKEY  面板「设置 → 密钥」里生成的 API Key（必填）
#   ONEPANEL_NODE    节点名称，留空表示主节点
#
# 退出码：0 成功；1 请求失败或 1Panel 返回非 200；3/4 环境变量不合法
# ============================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=check-env.sh
. "$SCRIPT_DIR/check-env.sh" refresh

# 规范化站点地址：去掉结尾斜杠，缺少协议时补 http://
ONEPANEL_URL="${ONEPANEL_URL%/}"
if [[ "$ONEPANEL_URL" != http://* && "$ONEPANEL_URL" != https://* ]]; then
    ONEPANEL_URL="http://${ONEPANEL_URL}"
fi

# md5 命令兼容 Linux(md5sum) 与 macOS(md5)
md5_hex() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | awk '{print $1}'
    else
        md5 -q
    fi
}

# 鉴权方式：Token = md5("1panel" + APIKey + Timestamp)
# 请求头需携带 1Panel-Timestamp / 1Panel-Token
# CurrentNode 可选：留空时不发送该头，1Panel 将默认为主节点
echo "🔄 Refreshing 1Panel local app store..."

# 任务 ID：优先用内核 UUID，其次 uuidgen，最后用随机数兜底（非 Linux 也能跑）
TASK_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || printf 'task-%s-%s' "$(date +%s)" "$RANDOM")"
TIMESTAMP=$(date +%s)

TOKEN=$(echo -n "1panel${ONEPANEL_APIKEY}${TIMESTAMP}" | md5_hex)

NODE_HEADER=()
if [[ -n "$ONEPANEL_NODE" ]]; then
    NODE_HEADER=(-H "CurrentNode: ${ONEPANEL_NODE}")
fi

RESPONSE=$(curl -ksS \
    -X POST \
    "${ONEPANEL_URL}/api/v2/apps/sync/local" \
    -H "Content-Type: application/json" \
    -H "1Panel-Timestamp: ${TIMESTAMP}" \
    -H "1Panel-Token: ${TOKEN}" \
    ${NODE_HEADER[@]+"${NODE_HEADER[@]}"} \
    -d "{\"taskID\":\"${TASK_ID}\"}") || {
    echo "❌ curl 请求失败，请检查 1Panel 地址与网络连通性。"
    exit 1
}

echo "1Panel response:"
echo "$RESPONSE"

if ! echo "$RESPONSE" | grep -q '"code":200'; then
    echo "❌ Failed to trigger 1Panel app store refresh."
    exit 1
fi

echo "✅ 1Panel local app store refresh triggered."
echo "TaskID: ${TASK_ID}"
