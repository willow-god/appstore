# MoonTV

MoonTV 是一款简洁易用的在线影视播放平台，支持在线播放电影、电视剧、综艺、动漫等视频内容。部署完成后可直接通过浏览器访问，无需客户端。

## 特性

* **一键部署**：Docker Compose 轻松启动
* **多端适配**：电脑、平板、手机均可访问
* **在线播放**：支持多种影视资源
* **界面简洁**：操作简单直观

## 部署

1. 拉取镜像并启动：

   ```bash
   docker compose up -d
   ```
2. 浏览器访问 `http://服务器IP:端口` 即可使用

## 默认信息

* 默认端口：`3000`（可在 Compose 文件中修改）

## 开源地址

[MoonTV on GitHub](https://github.com/LunaTechLab/MoonTV)
