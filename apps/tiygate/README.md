# TiyGate

TiyGate 是一款用 Rust 编写的开源 AI 网关，适合同时使用多个 LLM 服务商、订阅套餐、协议或 API Key 的个人与团队。

它通过统一控制面接入 OpenAI-Compatible、Responses、Messages、Gemini 等协议，并支持虚拟模型路由、请求日志、统计分析和密钥加密存储。

## 使用说明

- 本应用商店版本使用 SQLite，数据保存在应用目录的 `data/tiygate.db`。
- 安装完成后访问 `http://服务器IP:端口/admin/ui`。
- 登录时填写安装表单中生成或设置的管理员令牌。
- `TIYGATE_MASTER_KEY` 用于加密存储服务商 Key、OAuth token 和 S3 凭证。留空也可以启动，但密钥会明文存储；需要加密时请填写 64 位 hex 或标准 base64 格式的 32 字节密钥。
- `Redis 连接地址` 为可选项，仅在镜像包含 Redis 配额功能且需要跨副本共享计数时使用，例如 `redis://redis:6379/0`。

## 反向代理

如通过 1Panel 网站反向代理访问，请将目标地址设置为本应用的 HTTP 端口，并保留长连接/流式响应能力。

## 相关链接

- 项目地址：https://github.com/tiylabs/tiygate
- 中文文档：https://github.com/tiylabs/tiygate/blob/master/README_zh.md
