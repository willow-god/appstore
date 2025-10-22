#!/bin/bash

# ==============================================================================
# 数据目录迁移脚本 (最终确认版)
# 功能：将旧的 ./data 目录迁移到新的 ./data/ech0-data 结构。
# 执行逻辑：
#   1. 首次执行：
#      - 将旧的 ./data 重命名为 ./tmp (作为备份)。
#      - 创建新的 ./data/ech0-data 和 ./data/backup 结构。
#      - 从 ./tmp (备份) 复制数据到 ./data/ech0-data。
#   2. 二次执行：检测到迁移已完成，删除备份 ./tmp。
#   3. 后续执行：检测到一切就绪，直接退出。
# ==============================================================================

# --- 脚本配置 ---
OLD_DATA_DIR="./data"
TMP_BACKUP_DIR="./tmp" # 将作为 ./data 的备份
NEW_DATA_DIR="${OLD_DATA_DIR}/ech0-data"
BACKUP_MOUNT_DIR="${OLD_DATA_DIR}/backup"

# --- 脚本开始 ---

# 设置严格模式：遇到错误或未定义变量时立即退出
set -e
set -u

echo "=========================================================="
echo "数据目录迁移脚本"
echo "当前时间: $(date)"
echo "=========================================================="

# --- 步骤 1: 判断迁移是否已经完成 ---
# 如果新的数据目录已存在，说明迁移至少执行过一次了
if [ -d "$NEW_DATA_DIR" ]; then
    echo "检测到新的数据结构 $NEW_DATA_DIR 已存在。"

    # --- 步骤 1a: 判断是否需要清理备份 ---
    # 检查备份文件夹（tmp）是否还存在
    if [ -d "$TMP_BACKUP_DIR" ]; then
        echo "检测到备份文件夹 $TMP_BACKUP_DIR 仍然存在，正在清理..."
        echo "  -> 正在删除备份文件夹 $TMP_BACKUP_DIR ..."
        rm -rf "$TMP_BACKUP_DIR"
        echo "备份清理完成！所有迁移任务已结束。"
    else
        # 如果备份不存在，说明已经清理过了，无需任何操作
        echo "迁移已完成且备份已清理，无需任何操作。"
    fi
    
    echo "脚本退出。"
    exit 0
fi

# --- 步骤 2: 执行首次迁移 ---
# 如果能执行到这里，说明 ./data/ech0-data 不存在，需要进行首次迁移
echo "新的数据结构不存在，开始执行首次迁移..."

# 前置条件检查：确保源目录存在
if [ ! -d "$OLD_DATA_DIR" ]; then
    echo "错误：源目录 $OLD_DATA_DIR 不存在！无法执行迁移。"
    exit 1
fi

# 前置条件检查：确保备份目录不存在，防止意外覆盖
if [ -d "$TMP_BACKUP_DIR" ]; then
    echo "错误：备份目录 $TMP_BACKUP_DIR 已存在！为避免数据丢失，脚本中止。"
    echo "请手动检查并处理 $TMP_BACKUP_DIR 目录。"
    exit 1
fi

# 将旧的 ./data 目录重命名为 ./tmp
echo "  -> 将 $OLD_DATA_DIR 重命名为 $TMP_BACKUP_DIR 作为备份..."
mv "$OLD_DATA_DIR" "$TMP_BACKUP_DIR"

# 创建新的文件夹结构
echo "  -> 创建新的目录结构..."
mkdir -p "$NEW_DATA_DIR"
mkdir -p "$BACKUP_MOUNT_DIR"
echo "      已创建: $NEW_DATA_DIR"
echo "      已创建: $BACKUP_MOUNT_DIR"

# 从 tmp (备份) 复制数据到新的 ech0-data 目录
echo "  -> 从备份 $TMP_BACKUP_DIR 恢复数据到 $NEW_DATA_DIR ..."
cp -r "${TMP_BACKUP_DIR}/"* "$NEW_DATA_DIR/"

# 注意：首次执行后，我们特意保留 tmp 文件夹，作为原始备份

echo "=========================================================="
echo "首次迁移成功完成！"
echo ""
echo "新的目录结构已创建："
echo "  - $NEW_DATA_DIR (挂载到 /app/data)"
echo "  - $BACKUP_MOUNT_DIR (挂载到 /app/backup)"
echo ""
echo "原始数据已备份到: $TMP_BACKUP_DIR"
echo "下次运行脚本时将自动清理此备份。"
echo "=========================================================="

exit 0
