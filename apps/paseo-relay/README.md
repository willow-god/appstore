## Paseo Relay

[Paseo](https://github.com/getpaseo/paseo) 的自托管中继服务器。Paseo 守护进程和移动端能直连时不会经过它；只有在同一个网络里连不上（比如移动端在外网）时，才由中继转发两端的 WebSocket 流量。

中继是**零知识**的：两端用 XSalsa20-Poly1305（NaCl box）做端到端加密，中继只能看到 IP、时间、消息大小和会话 ID，读不到也伪造不了消息内容。

- 默认端口：`8411`（容器内同为 `8411`）
- 健康检查接口：`GET /health`
- 上游仓库：<https://github.com/zenghongtu/paseo-relay>
- 协议说明与威胁模型：<https://github.com/zenghongtu/paseo-relay#readme>

## 数据持久化

中继只在内存里转发数据帧，**没有需要持久化的目录**，不挂载 `/app/data`，也不会在升级或重装时丢配置。重启只会断开当前会话，守护进程和移动端会自动重连。

## 在 Paseo 守护进程里启用

编辑 `~/.paseo/config.json`，在 `daemon.relay` 下填入中继地址，然后重启守护进程：

```json
{
  "daemon": {
    "relay": {
      "enabled": true,
      "endpoint": "relay.example.com:8411",
      "publicEndpoint": "relay.example.com:8411"
    }
  }
}
```

```bash
paseo daemon stop && paseo daemon start
```

用域名并且前面套了反向代理时，把端口写成 `443` 并加 `"useTls": true`。

## 反向代理与 HTTPS

- 中继本身**不做 TLS**，请务必在前面套 nginx / Caddy / Cloudflare 等反向代理终止 TLS，不要把 8411 直接暴露成明文 HTTP。
- 反向代理需要支持 WebSocket（Upgrade / Connection 头透传）。
- 中继自身没有任何鉴权，安全性完全依赖端到端加密，所以暴露到公网时更要注意 TLS 配置。

## 说明

- 端口在安装时填写，之后也可以在面板的「参数」里修改。
- 日志格式固定为 `text`，便于在面板日志里直接阅读。
