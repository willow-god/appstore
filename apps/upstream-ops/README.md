# UpstreamOps

UpstreamOps 是面向 NewAPI / Sub2API 上游站点的集中监控与运维面板，同时提供兼容 OpenAI、Claude 和 Responses 的请求转发网关。

## 特性

- 监控多个上游的余额、消费、倍率、公告和订阅用量
- 管理上游 API Key、充值、兑换和通知渠道
- 提供模型映射、倍率调度、故障转移和请求用量记录
- 默认使用 SQLite，数据保存在应用数据目录中

## 配置说明

- `APP_SECRET` 用于加密敏感数据，安装时会自动生成随机值。请妥善保存，修改后已有密文无法解密。
- 默认关闭后台鉴权，适合内网或已由反向代理保护的部署。公网使用时请启用鉴权并设置管理员密码。
- 应用监听容器内 `8418` 端口，安装时可通过 HTTP 端口字段映射到主机端口。

项目文档：[README.zh.md](https://github.com/bejix/upstream-ops/blob/main/README.zh.md)
