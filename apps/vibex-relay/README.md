# Vibex Relay

🔐 **Vibex Relay** 是 [Vibex](https://github.com/vibex-ai/vibex) 的可选自托管中继。电脑和手机无法直连时，双方通过它转发**端到端加密**的 WebSocket 帧；中继只负责房间路由，不保存会话、文件或模型配置，也无法解密业务数据。

## 特点

- 零知识转发：Relay 只看到路由、连接数和时间等元数据
- 无网页界面：根路径 `/` 返回 404，只有健康检查、能力信息和 WebSocket 接口
- 纯内存运行：房间和连接在重启后清空，客户端会自动重连，不需要数据卷
- 多架构镜像：`linux/amd64`、`linux/arm64`

## 接口

| 路径 | 用途 |
| --- | --- |
| `GET /health` | 状态、运行时间、房间数和连接数 |
| `GET /api/info` | 能力开关与当前生效的限制 |
| `GET /ws` | 电脑与设备之间的全双工 WebSocket |

没有 `/api/v2/info`，那是 Vibex 运行时（`vibex-server`）的接口，不要和 Relay 混用。

## 访问方式

应用默认只把端口发布到宿主机 `127.0.0.1`，这是上游推荐的安全默认值。对外使用时请在前面放一层 HTTPS/WSS 入口，例如：

- **1Panel 反向代理**：网站 → 反向代理 → 目标 `http://127.0.0.1:9700`，开启证书；代理需要支持 `/ws` 的 WebSocket Upgrade
- **Caddy**：把 `/ws`、`/health`、`/api/*` 反代到 `127.0.0.1:9700`
- **Tailscale Serve**：`tailscale serve --bg http://127.0.0.1:9700`

不要直接把明文 HTTP 暴露到公网，也不要把 `Host` / `Origin` 校验改成 `*`。

验证：

```bash
curl -fsS http://127.0.0.1:9700/health
curl -fsS http://127.0.0.1:9700/api/info
```

然后在 Vibex 里把自托管 Relay 地址填成实际 HTTPS 地址，例如 `https://relay.example.com`，客户端会自动使用 `wss://relay.example.com/ws`。

## 环境变量

安装表单只暴露宿主机端口；容器内监听地址和常用上限已经固定：

| 变量 | 值 / 默认 | 说明 |
| --- | --- | --- |
| `PANEL_APP_PORT_HTTP` | `9700` | 宿主机回环端口 |
| `VIBEX_RELAY_BIND_ADDR` | `0.0.0.0:9700` | 容器内监听地址，固定 |
| `VIBEX_RELAY_ROOM_TTL_MS` | `3600000` | 房间空闲回收时间 |
| `VIBEX_RELAY_MAX_ROOMS` | `1024` | 最大房间数 |
| `VIBEX_RELAY_MAX_TOTAL_CONNECTIONS` | `4096` | 最大总连接数 |
| `VIBEX_RELAY_MAX_DEVICES_PER_ROOM` | `8` | 每个房间最大设备数 |
| `VIBEX_RELAY_MAX_WEBSOCKET_FRAME_BYTES` | `33554432`（32 MB） | 单个 WebSocket 帧上限，上游默认 2 MB |
| `VIBEX_RELAY_MAX_QUEUE_BYTES_PER_CONNECTION` | `67108864`（64 MB） | 每连接待发送队列上限，上游默认 4 MB |
| `VIBEX_RELAY_MAX_BODY_BYTES` | `8388608`（8 MB） | HTTP 请求体上限，上游默认 1 MB |

上游文档里的这三个默认值偏小，稍大的消息会触发断连；本应用已在 `docker-compose.yml` 中放大（已向上游反馈）。其余限流、队列、带宽、推送适配器等 `VIBEX_RELAY_*` 变量仍使用上游默认值；需要调整时在 1Panel 应用的 `docker-compose.yml` 里追加后重建容器。

## 项目地址

- 项目主页：<https://vibex.peatboy.com>
- GitHub：<https://github.com/vibex-ai/vibex>
- Relay 文档：<https://vibex.peatboy.com/docs/en/relay>
- 镜像：`ghcr.io/vibex-ai/vibex-relay:0.1.9`
