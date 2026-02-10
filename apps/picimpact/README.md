- PicImpact 是一个支持自部署的摄影作品展示网站，基于 Next.js + Hono.js 开发。

  ### 功能特性

  - 瀑布流相册展示图片，支持[实况照片(Live Photos)](https://support.apple.com/zh-cn/104966)，基于 [LivePhotosKit JS](https://developer.apple.com/documentation/livephotoskitjs) 开发。
  - 基于 WebGL 的高性能图片查看器，支持流畅的缩放和平移，采用图片分块（Tiling）和 LOD 技术优化大图加载性能。
  - 支持地图模组标记图片，根据图片经纬度标记在地图上。
  - 点击图片查看原图，浏览图片信息和 EXIF 信息，支持直链访问。
  - 响应式设计，在 PC 和移动端都有不错的体验，支持暗黑模式。
  - 图片存储兼容 S3 API、Cloudflare R2、Open List API。
  - 图片支持绑定标签，并且可通过标签进行交互，筛选标签下所有图片。
  - 支持输出 RSS，可以使用 [Follow](https://github.com/RSSNext/Follow) 订阅，并支持订阅源所有权验证。
  - 支持批量自动化上传，上传图片时会生成 0.3 倍率的压缩图片，以提供加载优化。
  - 后台有图片数据统计、图片上传、图片维护、相册管理、系统设置和存储配置功能。
  - 双因素认证功能，基于 TOTP 算法 [RFC 6238](https://www.rfc-editor.org/rfc/rfc6238)，支持 Google Authenticator、Microsoft Authenticator 和 1Password 等。
  - Passkey 无密码登录功能，基于 WebAuthn 标准，支持生物识别（指纹、面容等）和硬件安全密钥登录。
  - 基于 SSR 的混合渲染，采用状态机制，提供良好的使用体验。
  - 基于 prisma 的自动初始化数据库和数据迁移，简化部署流程。
  - 支持 Vercel 部署、Node.js 部署、Docker 等容器化部署，当然 k8s 也支持。
