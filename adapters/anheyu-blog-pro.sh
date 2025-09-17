#!/bin/bash
set -euo pipefail

# ============================================================
# 查找 ./app/anheyu-blog-pro/**/docker-compose.yml
# 并将 anheyu/anheyu-backend: 替换为 harbor.anheyu.com/anheyu/pro:v
# ============================================================

TARGET_DIR="./apps/anheyu-blog-pro"
SEARCH_PATTERN="docker-compose.yml"
SRC="anheyu/anheyu-backend:"
DST="harbor.anheyu.com/anheyu/pro:v"

# 查找目标文件
files=$(find "$TARGET_DIR" -type f -name "$SEARCH_PATTERN")

if [ -z "$files" ]; then
  echo "未找到任何 $SEARCH_PATTERN 文件"
  exit 0
fi

for file in $files; do
  echo "处理文件: $file"
  # 先备份
  cp "$file" "${file}.bak"

  # 用 sed 替换
  sed -i "s|$SRC|$DST|g" "$file"

  echo "已替换 $SRC -> $DST"
done
