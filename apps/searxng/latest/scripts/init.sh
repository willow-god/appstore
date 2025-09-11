#!/bin/bash
set -e

ENV_FILE=".env"
SETTINGS_FILE="./data/searxng/settings.yml"

# 1. 检查 .env 文件
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 未找到 $ENV_FILE，请先生成 .env 文件"
  exit 1
fi

# 2. 导入环境变量
export $(grep -v '^#' "$ENV_FILE" | xargs)

# 3. 生成 Redis URL
REDIS_URL="redis://"
if [ -n "$PANEL_REDIS_ROOT_PASSWORD" ]; then
  REDIS_URL="${REDIS_URL}:$PANEL_REDIS_ROOT_PASSWORD@"
fi
REDIS_URL="${REDIS_URL}${PANEL_REDIS_HOST}:6379/${REDIS_DB}"

echo "✅ 生成的 Redis URL: $REDIS_URL"

# 4. 检查 settings.yml 是否存在
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "❌ 未找到 $SETTINGS_FILE"
  exit 1
fi

# 先备份
cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

# 5. 处理 secret_key
if grep -q 'secret_key: ${SECRET_KEY}' "$SETTINGS_FILE"; then
  NEW_KEY=$(openssl rand -hex 32)
  sed -i "s|secret_key: \${SECRET_KEY}|secret_key: \"$NEW_KEY\"|" "$SETTINGS_FILE"
  echo "🔑 已生成新的 secret_key: $NEW_KEY"
else
  echo "ℹ️ secret_key 已经设置过，跳过替换"
fi

# 6. 处理 redis.url
if grep -q 'url: ${REDIS_CONNECT_URL}' "$SETTINGS_FILE"; then
  sed -i "s|url: \${REDIS_CONNECT_URL}|url: ${REDIS_URL}|" "$SETTINGS_FILE"
  echo "🔄 已替换 Redis URL"
else
  echo "ℹ️ Redis URL 已经设置过，跳过替换"
fi

echo "✅ 初始化完成（原文件已备份为 $SETTINGS_FILE.bak）"
