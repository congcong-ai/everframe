# EverFrame 官网

正式地址：[everframe.bebackpacker.com](https://everframe.bebackpacker.com)。

独立的中文产品首页，与手机应用内 `EverFrame/Web/` 局域网控制界面分开维护。使用原生 HTML、CSS、JavaScript 和 Node.js，无第三方运行依赖，无需 Docker 或构建步骤。

## 本地运行

需要 Node.js 22 或更新版本。

```sh
cd website
pnpm dev
```

访问 http://localhost:3000。开发入口会先终止所选端口的监听进程，再启动服务；可用 `PORT=3001 pnpm dev` 更换端口。

```sh
pnpm test
```

## 下载

`/download/android` 实时读取公开 GitCode Releases，按语义版本选择最新的已上传 Android APK（包括预览版），返回无缓存的 302，不代理安装包。公开查询不需要 Token。API 故障时回退已发布的 GitCode v0.1.1 下载直链。更新回退版本时修改 `download.mjs` 的 `fallbackAPK`。

iOS 显示“正在申请 App Store 上架中”，没有虚构的商店下载链接。

## 托管

在项目根目录配置 `.deploy.env`，使用 `pnpm server:install` 完成首次安装和首次发布，后续使用 `pnpm server:deploy`。详见[官网部署文档](../docs/DEPLOYMENT.md)。

生产服务只监听 `127.0.0.1` 的审计确认端口，由 Nginx 提供 HTTPS。需要运行 Node 服务以支持 `/download/android`；单独上传静态文件无法提供动态下载入口。`/healthz` 用于健康检查。

## 设计与素材

电影取景框、绿色点缀与编辑式排版，参考 [Dribbble 摄影落地页的排版方向](https://dribbble.com/shots/27627101-Atelier-Noir-Editorial-Photography-Landing-Page)，独立实现页面与交互。支持移动端、键盘操作与系统减少动态效果偏好。

场景图片是示意摄影，不是应用实拍：

- 森林：https://images.unsplash.com/photo-1441974231531-c6227db76b6e
- 创作：https://images.unsplash.com/photo-1513364776144-60967b0f800f
- 猫咪：https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba

图片存于 `assets/`，页面无外部字体、脚本或图片运行依赖。

## 开源、隐私与检索

首页明确展示 GitHub 与 GitCode 源码地址；`/privacy` 说明本机保存及可选联网功能的数据边界。首页提供产品问答入口和 SoftwareApplication、SoftwareSourceCode JSON-LD，`/faq` 提供完整可直接阅读的 FAQ 与一致的 FAQPage JSON-LD；`/robots.txt` 允许抓取内容页，`/llms.txt` 提供简短产品事实与原始资料链接。正式域名为 `https://everframe.bebackpacker.com`；canonical 和站点地图统一使用此地址，`generate-content.mjs` 保存对应的 `origin`。

这些内容有助于理解与引用，不保证收录、排名或 AI 推荐。Google 的 FAQ 富结果主要限政府和健康网站，本站不以此宣称可获得富结果。

## Android 发布到 GitCode

源码仓库：[GitCode · xixisys/everframe](https://gitcode.com/xixisys/everframe)。根目录 `.env` 配置 `GITCODE_OWNER`、`GITCODE_REPO`、`GITCODE_TOKEN`，不要提交凭据。

从项目根目录运行：

```sh
node scripts/publish-android.mjs v0.1.1 artifacts/android/everframe-android-v0.1.1-debug.apk
```

脚本发布已有 APK 和同名 `.sha256`，真实下载远端附件并比较 SHA-256。不重新构建、不删除本地包、不覆盖冲突附件。后续版本使用相同命名规则；官网每次点击实时选择可用的最高版本，包括明确标记的预览版。下载探针兼容 GitCode HEAD 401、GET 302 的行为；只检查响应头，不代理安装包。发布 Token 仅发布脚本使用，不进入页面或下载跳转。

## 更新产品问答

根目录 README 的“常见问题”是详细问答的内容来源。修改后从项目根目录运行：

```sh
node website/generate-content.mjs
pnpm --dir website test
```

生成 `faq.html`、页面 canonical、`sitemap.xml` 和 `robots.txt`。答案直接存在 HTML 中，无需 JavaScript、登录或 API。首页保持简短，用普通链接指向专题页。`llms.txt` 是辅助产品事实说明，不是已被所有 AI 平台采纳的标准。
