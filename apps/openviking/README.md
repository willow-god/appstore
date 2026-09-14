# OpenViking

<div align="center">
  <img src="logo.png" alt="OpenViking" width="200" height="200">
</div>

OpenViking 是面向 AI Agent 的开源上下文数据库，用统一的文件系统范式管理记忆、资源和技能，并支持语义检索与层级式上下文加载。

## 使用说明

- 应用商店版本使用 `v0.4.20` 镜像标签，便于应用商店检测后续版本更新。
- 默认访问端口为 `1933`，安装时可在 HTTP 端口字段中修改主机端口。
- 数据保存在应用目录下的 `data` 文件夹中。
- 官方 compose 中的 Caddy 仅用于可选的公网 HTTPS 入口，本应用商店版本直接暴露 OpenViking 服务端口，建议通过 1Panel 反向代理配置域名和 HTTPS。

## 配置说明

- `OPENVIKING_PUBLIC_BASE_URL`：公网访问地址，仅在需要公网 HTTPS（OAuth、外部 MCP 客户端等）时填写，例如 `https://ov.example.com`。纯内网或仅通过 IP 访问时可以留空。

## GHCR 镜像配置

Compose 中固定使用带版本号的官方镜像：

```text
ghcr.io/volcengine/openviking:v0.4.20
```

本仓库通过根目录的 `mirror.sh` 和服务器上的 `/opt/mirror-config.env` 统一处理 GHCR 镜像替换，不在应用表单中把镜像地址作为可变变量。这样可以保留版本检测和自动更新能力。

项目地址：[OpenViking](https://github.com/volcengine/OpenViking)
