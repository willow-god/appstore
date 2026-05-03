# NapCat

## 基于 NTQQ 的现代化 QQ Bot 框架

### 项目简介

NapCat 是基于 NTQQ 本地客户端实现的高性能 QQ Bot 框架，支持 OneBot 11 / OneBot 12 协议，提供 WebUI 管理界面，让您可以快速搭建属于自己的 QQ 机器人。

### 核心特性

- 基于 NTQQ 本地客户端，稳定可靠
- 支持 OneBot 11 / OneBot 12 协议
- 提供 WebUI 管理界面，方便配置与监控
- 支持 HTTP / WebSocket / 反向 WebSocket 多种通信方式
- 插件化架构，易于扩展
- 支持多平台（Linux amd64 / arm64）

### 持久化路径

| 容器内路径 | 本地路径 | 说明 |
|------------|----------|------|
| `/app/.config/QQ` | `./data/qq` | QQ 账号数据持久化 |
| `/app/napcat/config` | `./data/config` | NapCat 配置文件 |
| `/app/napcat/plugins` | `./data/plugins` | NapCat 插件目录 |

### 端口说明

| 端口 | 用途 |
|------|------|
| `3000` | OneBot HTTP API 端口 |
| `3001` | OneBot HTTP Event 端口 |
| `6099` | WebUI 管理界面端口 |

### 快速开始

部署完成后，访问 `http://<宿主机IP>:6099/webui` 进入 WebUI 管理界面。

默认登录 Token：`napcat`

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `NAPCAT_UID` | 运行 QQ 进程的用户 ID | `0` |
| `NAPCAT_GID` | 运行 QQ 进程的组 ID | `0` |

### 相关链接

- 官方文档：https://napneko.github.io/
- GitHub：https://github.com/NapNeko/NapCatQQ
- DockerHub：https://hub.docker.com/r/mlikiowa/napcat-docker
