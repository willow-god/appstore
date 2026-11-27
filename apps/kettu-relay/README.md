# Kettu Relay

🦊 **Kettu Relay** 是 [Kettu](https://github.com/KettuAI/Kettu) 的自托管中继。运行 Kettu 的电脑用中继的访问密钥签入，手机、浏览器和其他电脑再通过中继从任意网络访问这些电脑，不需要注册 Kettu 账号。

中继只转发 Kettu 的**端到端加密**通道，看不到会话、文件和密钥；也不保存连接信息，磁盘上只有访问密钥、证书和一份 Web 客户端。

## 特点

- 零知识转发：中继只看到连接来源、电脑的中继 ID 以及加密消息的大小和时间
- 自带 Web 客户端：浏览器打开中继地址即可配对和运行会话；桌面端和 iPhone 端不依赖它
- 反向代理模式：本应用以 HTTP 跑在 `127.0.0.1` 的内网端口上，TLS 交给 1Panel 反向代理
- 纯中继无状态：只需持久化 `/data`（访问密钥和 Web 客户端），不保存会话或文件
- 多架构镜像：`linux/amd64`、`linux/arm64`

## 访问方式

本应用采用中继的**反向代理模式**（`KETTU_RELAY_URL`）：中继在容器内监听 `0.0.0.0:8798`，宿主机只发布到 `127.0.0.1`，由 1Panel 反向代理对外提供 HTTPS。不要把这个端口直接暴露到公网 —— 中继在这个端口上说的是明文 HTTP，只接受受信反向代理的连接。

安装后按下面步骤接入：

1. **建反向代理网站**：1Panel → 网站 → 反向代理 → 目标地址 `http://127.0.0.1:8798`，开启 HTTPS 证书。
2. **确认 WebSocket**：反向代理必须传递 `Upgrade` / `Connection` 头，并把读超时调长，中继和 Web 客户端依赖长连接。1Panel 较新版本的反向代理模板通常已带 Upgrade 头；若会话频繁断开，在代理配置中补充：

   ```nginx
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_read_timeout 1h;
   ```

3. **取得接入链接**：

   ```bash
   docker exec <容器名> kettu-relay link
   ```

   输出形如 `https://relay.example.com#key=krk_...`，其中包含中继地址和访问密钥。
   （容器名就是安装时填写的名称；首次启动时完整链接也会打印在容器日志里一次，之后只打印打码后的地址。）

4. **填入 Kettu**：在每台电脑的 Kettu 中打开 **设置 › 远程访问 › Relay › 使用自己的中继**，粘贴链接并选择「使用此中继」。设备照常用「添加设备」配对，配对码会带上中继地址，但不会带上密钥。

### 受信反向代理

反向代理模式下，中继**只接受 `KETTU_RELAY_TRUSTED_PROXIES` 里地址的连接**，也只采信这些地址发来的 `X-Forwarded-For`（用于按客户端地址限流）。

默认值 `127.0.0.0/8,::1/128,172.16.0.0/12` 覆盖回环和 Docker 网桥网段：宿主机 `127.0.0.1` 的端口转发进入容器后，来源地址是 Docker 网桥地址（通常是 `172.17.0.1` / `172.18.0.1`）。如果服务器的 `1panel-network` 使用 `10.x` 或 `192.168.x` 网段，请把安装表单里的这一项改成实际网段，否则中继会拒绝所有连接。

## 环境变量

安装表单只暴露端口、对外地址和受信反向代理；容器内监听地址和数据目录固定：

| 变量 | 值 / 默认 | 说明 |
| --- | --- | --- |
| `PANEL_APP_PORT_HTTP` | `8798` | 宿主机回环端口，供反向代理使用 |
| `KETTU_RELAY_URL` | 必填，例如 `https://relay.example.com` | 对外 HTTPS 地址，必须与反向代理域名一致 |
| `KETTU_RELAY_TRUSTED_PROXIES` | `127.0.0.0/8,::1/128,172.16.0.0/12` | 允许连接并采信 `X-Forwarded-For` 的地址或 CIDR |
| `KETTU_RELAY_LISTEN` | `0.0.0.0:8798` | 容器内监听地址，固定 |
| `KETTU_RELAY_DATA` | `/data` | 数据目录，固定 |

上游还支持限流、连接数、加入超时等设置（如 `KETTU_RELAY_CONNECTIONS_PER_MINUTE`、`KETTU_RELAY_MAX_CONNECTIONS`、`KETTU_RELAY_MAX_PENDING_DEVICES`、`KETTU_RELAY_JOIN_TIMEOUT`），需要调整时在 1Panel 应用的 `docker-compose.yml` 里追加后重建容器，完整列表见[部署文档](https://github.com/KettuAI/relay/blob/main/docs/deploy.md)。

## 数据与升级

- `/data` 挂载到应用目录的 `./data`，保存访问密钥和 Web 客户端；升级或重建容器时请保留它，不要执行 `docker compose down -v`。
- 删除 `./data` 等于换一把新密钥，已签入的电脑会全部断开，需要重新粘贴新链接。
- 镜像以 uid/gid `65532` 运行，且启动时要求数据目录属主是自己、权限为 `0700`；`scripts/init.sh` 会在容器启动前准备好目录，如果手动迁移过数据目录，记得重新执行一次 `chown -R 65532:65532 ./data`。

### 重置访问密钥

```bash
docker exec <容器名> kettu-relay key reset
docker exec <容器名> kettu-relay link
```

旧密钥签入的电脑会在几秒内被断开，把新链接重新粘贴到每台电脑即可。持有链接的人都能把电脑签入中继，链接一旦泄露请立即重置。

## 项目地址

- 项目主页：<https://www.kettu.sh>
- GitHub：<https://github.com/KettuAI/relay>
- Kettu 主程序：<https://github.com/KettuAI/Kettu>
- Relay 部署文档：<https://github.com/KettuAI/relay/blob/main/docs/deploy.md>
- 镜像：`ghcr.io/kettuai/relay:0.1.2`
