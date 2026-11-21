# DS Harness Remote

🛰️ **DS Harness Remote** 是 DS Harness 的自托管远程接入服务器：Host 与客户端都连接到它，用同一个账号登录后即可建立加密的远程会话。

## 功能

- 设备注册、凭据刷新与设备发现
- 协调 WebRTC 连接（LAN → P2P → TURN），无法直连时自动回退到端到端加密 Relay
- Web 控制台：首页 `/` 登录，`/app/remote` 查看已授权设备
- 单进程运行，设备凭据和状态保存在 `./data/state.json`

## 部署后

1. 打开 `http://服务器地址:端口/`，点击「开始使用」登录。
2. Host 和客户端填写同一个服务器地址，并使用相同的账号密码登录。
3. 通过域名或反向代理访问时，必须把「访问地址」改成浏览器实际访问的 origin，例如 `https://remote.example.com`。协议、域名、非默认端口都要一致，否则首页能打开但 JS/CSS 会返回 403，页面白屏。
4. 修改端口、域名或环境变量后，在 1Panel 中重建容器；仅「重启」不会重新加载环境变量。

## 反向代理

- 公网访问请使用 HTTPS 反向代理，不要直接把端口暴露到公网。
- 代理必须支持 `/ws/v1/connect` 的 WebSocket Upgrade，并把空闲超时设为大于 75 秒。
- 默认按连接的来源 IP 限流。经过反向代理后所有请求都来自代理，如需按真实客户端 IP 限流，可在应用的 `docker-compose.yml` 中追加 `DSH_SERVER_TRUSTED_PROXY_IPS`（填写代理在容器内看到的 IP，逗号分隔）；同时代理必须覆盖 `X-Forwarded-For`，且后端端口不能直接暴露到公网。

## 数据与升级

- 设备凭据和状态文件保存在安装目录下的 `./data` 中（挂载到容器 `/data`，状态文件为 `/data/state.json`）。
- 镜像以非 root 用户 `node`（uid/gid 1000）运行，而 `./data` 首次由 Docker 以 root 创建，容器会因无写权限报 `EACCES: /data/state.json.tmp`。
- 仓库的 `adapters/ds-harness-remote.sh` 会在每次执行 `scripts/mirror.sh` 时自动把已安装实例的 `data` 目录属主修正为 `1000:1000`，容器下一次自动重启即可恢复。也可以手动执行一次：

  ```bash
  PANEL_ROOT=/opt/1panel bash adapters/ds-harness-remote.sh
  ```

- 如果首次安装后立即启动报 `EACCES`，等下一次定时任务，或手动执行一次 `scripts/mirror.sh` / 上面的命令即可。
- 升级、重建容器时请保留 `./data`，不要执行 `docker compose down -v`。
- 修改登录密码后，已授权设备需要重新授权。

## 环境变量

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `PANEL_APP_PORT_HTTP` | 对外 HTTP 端口 | `8080` |
| `DSH_SERVER_ACCOUNT` | 登录账号，Host 与客户端共用，建议使用邮箱 | 必填 |
| `DSH_SERVER_PASSWORD` | 登录密码，至少 12 个字符 | 必填 |
| `DSH_SERVER_PUBLIC_URL` | 浏览器实际访问地址，必须与 origin 一致 | `http://localhost:8080` |

容器内监听地址、端口和状态文件路径已经固定（`0.0.0.0:8080`、`/data/state.json`），无需配置。

## WebRTC / TURN（可选）

默认只使用加密 Relay，不依赖 STUN/TURN。需要 LAN/P2P 直连或自建 TURN 时，在应用的 `docker-compose.yml` 中追加 `DSH_SERVER_STUN_URLS`、`DSH_SERVER_TURN_URLS` 以及对应的 TURN 密钥或用户名密码，再重建容器。TURN 通常需要单独部署 coturn，UDP/TCP 3478 和 relay 端口段要对 Host 与客户端可达。

## 项目地址

- GitHub: [https://github.com/liguobao/ds-harness-remote](https://github.com/liguobao/ds-harness-remote)
- 中文文档: [apps/server/README.zh.md](https://github.com/liguobao/ds-harness-remote/blob/main/apps/server/README.zh.md)
