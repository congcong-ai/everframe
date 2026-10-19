# 官网首次安装与日常部署

官网：[everframe.bebackpacker.com](https://everframe.bebackpacker.com)。部署对象仅为 `website/`，不涉及手机录像素材与局域网控制服务。

## 配置与目录

沿用 FDE 国内服务器配置：`deployer@49.235.209.193:22`、TLS 邮箱 `revival.wgj@gmail.com`。本站使用独立用户 `everframe`，PM2 进程 `everframe-web`，systemd 单元 `pm2-everframe`，Nginx 站点 `/etc/nginx/sites-available/everframe`。

```text
/var/www/everframe/
├── current -> releases/<版本号>
├── releases/                 # 当前健康版本和最近一个健康版本
└── shared/
    ├── .env                  # 生产运行配置，不进入发布包
    ├── install.env           # 非敏感安装信息
    ├── installed             # HTTPS 验收成功后写入的完成标记
    ├── deploy.lock           # 安装和发布共用互斥锁
    └── logs/
/var/lib/everframe/.pm2/       # 本站独立 PM2 状态
```

官网使用原生 Node.js 22+，无第三方应用运行依赖，无数据库、Docker 或服务端构建步骤。复用服务器已有兼容 Node.js、PM2、Nginx 和 Certbot，不升级共享服务器运行时。缺少系统包时先模拟安装，若涉及升级或删除现有包则停止。

## 首次安装

在项目根目录执行：

```sh
pnpm install --frozen-lockfile
cp .deploy.env.example .deploy.env
pnpm server:ports
```

将域名 A 记录指向 `49.235.209.193`。审计工具合并实时监听、Nginx、PM2、systemd 等配置；确认端口后填写 `.deploy.env` 的 `DEPLOY_WEB_PORT`。本次安装确认的端口为 `3020`，只监听 `127.0.0.1`。

```sh
pnpm server:install --check    # 只检查本地配置
pnpm server:install           # 安装并完成首次发布
```

首次入口先只读检查安装标记；安装已完成时不再测试、打包或上传。未完成时依次测试官网、检查脚本、按白名单打包、上传、校验 SHA-256，创建独立用户和配置，启动官网、配置 PM2 自启和 Nginx，签发证书并验证 HTTPS 后写入安装标记。

运行配置位于服务器 `/var/www/everframe/shared/.env`，包含 `NODE_ENV`、`APP_ORIGIN`、`HOST`、`PORT`。官网公开下载查询无需 Token，无需复制根 `.env` 中的 GitCode 发布凭据。若需要修改域名或端口，应同时核对本地部署配置、Nginx 与官网 canonical/站点地图；普通发布不会自动迁移域名或端口。

## 日常部署

```sh
pnpm server:deploy
```

日常部署测试通过后上传独立发布包；不会上传 `.env`、Git、本机依赖、移动端源码、APK 或签名文件。服务器使用互斥锁，复制到新 release，停止本站旧进程并再次审计端口，然后原子切换 `current`、启动服务并验证健康接口与公开页面。失败自动恢复上一版，成功后保存 PM2 状态，仅保留当前版和最近一个健康旧版。

启动前只清理本站进程，发现其它项目占用端口时中止。重启会有短暂中断。官网无编译和运行依赖安装步骤，发布包直接携带 HTML、CSS、JS、素材和服务脚本。

部署配置中的代理默认关闭：

```dotenv
DEPLOY_USE_PROXY=false
DEPLOY_PROXY_HOST=127.0.0.1
DEPLOY_PROXY_PORT=1080
DEPLOY_HTTP_PROXY_PORT=1087
```

开启后仅用于安装进程的网络请求，应用进程不继承代理。配置读取顺序为根 `.env`、`.deploy.env`；后者覆盖同名项。`.deploy.env` 已 Git 忽略，示例可提交。

## 首次上线记录

2026-10-19 完成首次安装与 HTTPS 发布，生产进程只监听 `127.0.0.1:3020`。证书由 Let’s Encrypt 签发，首次证书到期日为 2027-01-17，已配置自动续期。后续证书日期以服务器实际状态为准。

## 验收与日志

```sh
curl -fsS https://everframe.bebackpacker.com/healthz
curl -I https://everframe.bebackpacker.com/
curl -I https://everframe.bebackpacker.com/privacy
curl -I https://everframe.bebackpacker.com/sitemap.xml
curl -sS -D - -o /dev/null https://everframe.bebackpacker.com/download/android
ssh deployer@49.235.209.193 'sudo nginx -t'
ssh deployer@49.235.209.193 'sudo systemctl is-active pm2-everframe; sudo systemctl is-enabled pm2-everframe'
ssh deployer@49.235.209.193 'sudo -u everframe env HOME=/var/lib/everframe PM2_HOME=/var/lib/everframe/.pm2 pm2 status'
```

`/healthz` 返回 `{"status":"ok","service":"everframe-website"}`。下载接口应返回带 `Cache-Control: no-store` 的 302；安装包由 GitCode/CDN 提供。应用日志位于 `/var/www/everframe/shared/logs/`。

本地独立打包检查：`bash scripts/build-release.sh /tmp/everframe-release-review`，该目录包含归档、SHA-256 文件和 `latest-release.txt`。

## 失败恢复

首次安装若因 DNS 或证书申请失败，HTTP 服务与配置会保留，不写安装完成标记；修正解析后重跑 `pnpm server:install` 可继续。日常发布必须已有完成标记。

发布失败会尝试自动恢复旧版。如果需要人工恢复，先查看 `releases/` 与当前指向，选定先前健康版本，在服务器持有 `shared/deploy.lock` 的条件下停止本站进程、切回旧版、重启 PM2 并验收；不要删除 `shared/.env` 或覆盖其它项目配置。回滚不涉及数据库，本官网没有数据库。

证书续期由已有 Certbot 定时任务处理，可用 `sudo systemctl status certbot.timer` 检查。
