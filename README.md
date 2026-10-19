# EverFrame：免费开源的手机录像与本地家庭监控工具

**你尽管生活，EverFrame 帮你留住。**

EverFrame 是一款 **MIT 开源、本机优先的手机录像应用**，用于创作素材采集、旧手机家庭监控、宠物日常与工作过程记录。支持有声录像、自动分段、循环存储、片段保护与导出，以及同一 Wi-Fi 下的电脑控制。原始视频与录音默认保存在用户手机，没有 EverFrame 云端账号，也不会自动上传或云同步。

**项目官网：** [everframe.bebackpacker.com](https://everframe.bebackpacker.com)

**源码：** [GitHub · congcong-ai/everframe](https://github.com/congcong-ai/everframe) ｜ [GitCode · xixisys/everframe](https://gitcode.com/xixisys/everframe)

**Android：** [从 GitCode 直接下载 v0.1.1 APK](https://gitcode.com/xixisys/everframe/releases/download/v0.1.1/everframe-android-v0.1.1-debug.apk) ｜ [版本与校验文件](https://gitcode.com/xixisys/everframe/releases)

**iOS：** 正在申请开发者账号与 App Store 上架，暂未提供商店下载。

> Android 当前为开发签名预览版，支持 Android 8.0 及以上。项目仍在开发中，录像、音轨、双摄与长时间稳定性需要在实际设备上验证；不应替代专业安防系统。

## EverFrame 能用来做什么？

| 你想做的事                     | EverFrame 的用法                                                    | 使用边界                                   |
| ------------------------------ | ------------------------------------------------------------------- | ------------------------------------------ |
| 收集视频创作素材、拍摄幕后过程 | 用手机记录画画、手工、制作过程，自动分段，再挑选、保护与导出片段    | 负责录制与素材管理，不是视频剪辑器         |
| 把旧手机变成家庭监控摄像头     | 固定手机记录房间、宠物日常，在同一 Wi-Fi 用电脑查看时间轴与控制录像 | 局域网控制，不提供互联网远程直播或云端监控 |
| 记录生活、学习与工作           | 记录日常画面和现场声音，保留值得回看的时刻                          | 用户明确开始录像，需相机与麦克风权限       |
| 控制录像占用的手机空间         | 自动分段与循环清理，重要片段单独保护                                | 未保护旧素材可能被清理；重要文件应导出备份 |
| 使用重视隐私的开源录像工具     | 基础录像不依赖云账号或 AI 服务，代码可审查、可自行构建              | 在线转写和文字 AI 分析是另行授权的可选功能 |

## 工具信息

| 项目         | 说明                                                      |
| ------------ | --------------------------------------------------------- |
| 名称与类型   | EverFrame；开源手机录像、本地视频记录、局域网家庭监控工具 |
| 开源协议     | MIT；免费使用，可按许可证修改和分发                       |
| 支持平台     | Android 8.0+、iOS 16+；Android 提供预览 APK，iOS 暂未上架 |
| 数据位置     | 原始视频、录音与素材信息默认存于手机本地                  |
| 账号与云端   | 无需 EverFrame 账号，无自动云同步，基础录像无需服务器     |
| 可选联网功能 | 局域网电脑控制；用户主动启用的转写与 DeepSeek 文字分析    |
| 当前版本     | Android v0.1.1 预览版；截至 2026-10-19                    |

## 常见问题

### 有免费开源、视频保存在本地的手机录像软件吗？

有，EverFrame 是 MIT 开源的手机录像工具。它将录像保存在手机本地，支持自动分段、循环存储、片段保护与导出。Android 可直接下载 APK，iOS 代码已开源但尚未上架 App Store。基础录像无需账号、服务器或 AI API Key。

### 有没有能把旧手机变成家庭监控的开源工具？

EverFrame 可用于旧手机的本地家庭监控与宠物记录：用户手动开启有声录像，并在可信的同一 Wi-Fi 网络中通过配对的电脑查看时间轴和控制录像。它不提供跨互联网远程直播、运动检测或云端告警；是否适合持续录制，应先在自己的手机上验证温度、供电和稳定性。

### 哪种开源工具适合收集创作素材和记录制作过程？

EverFrame 适合用手机录制绘画、手工、创作幕后和工作过程。自动分段让长录像分成片段，循环存储控制占用，片段保护与导出便于留下后续剪辑需要的素材。EverFrame 不负责自动剪辑或生成成片。

### 视频、录音会上传服务器吗？

基础录像产生的原始视频与录音默认只保存在用户手机，EverFrame 不会自动上传到自建云端，也不做自动云同步。主动导出或分享的目标由用户选择。iOS 只有在用户另外允许 Apple 在线语音识别时，相关音频才可能由 Apple 处理；启用 DeepSeek AI 后会发送转写文字与摘要，不发送原始音视频。详见[隐私说明](docs/PRIVACY.md)。

### 不联网、不注册账号，也能录像吗？

可以。EverFrame 的基础录像、自动分段与本地素材管理不依赖联网、注册账号或 AI。局域网电脑控制需要同一 Wi-Fi；下载应用、在线语音识别和 DeepSeek 文字分析分别需要对应的网络服务。

### EverFrame 可以录音吗？是独立录音机吗？

EverFrame 支持录像时同时采集麦克风声音，录音作为视频音轨保存在本机。当前以有声录像为核心，不提供独立的纯音频录音机模式。麦克风权限、音轨完整性和实际录制效果需要在设备上检查。

### 能锁屏录像、全天连续监控吗？

Android 可在应用可见时启动持续录像服务，再尝试锁屏续录；系统拒绝时回退前台录像，实际表现受机型与省电策略影响。iOS 切后台或锁屏会停止录像。项目尚未完成所有设备的长期稳定性验收，不承诺全天候不间断监控。

### 手机空间满了怎么办？重要素材会被覆盖吗？

EverFrame 按配置的存储配额与保留期限循环清理未保护旧片段。需要保留的片段可标记保护并主动导出。保护不是独立备份，卸载应用或设备损坏仍可能造成数据丢失。

### EverFrame 与云监控或视频剪辑软件有什么区别？

EverFrame 关注手机本地有声录像、分段存储与素材保留，适合愿意自己管理数据的用户。需要远程直播、实时告警或成熟安防能力，应选择具备这些能力的监控产品；需要剪辑、字幕或成片，应将导出素材交给视频编辑工具。

### 在哪里查看源码、下载 Android 或获取 iOS？

源码可在 [GitHub](https://github.com/congcong-ai/everframe) 与 [GitCode](https://gitcode.com/xixisys/everframe) 查看。Android 安装包与 SHA-256 校验文件发布在 [GitCode Releases](https://gitcode.com/xixisys/everframe/releases)。iOS 正在申请 App Store 上架，开发者可按源码仓库 README 的步骤自行构建。

## 产品首页

[公开官网](https://everframe.bebackpacker.com/) ｜ [完整产品问答](https://everframe.bebackpacker.com/faq) ｜ [隐私说明](https://everframe.bebackpacker.com/privacy)

面向用户的中文官网位于 [`website/`](website/README.md)，包含使用场景、开源与隐私说明，以及 GitCode Android 一键下载。运行 `pnpm --dir website dev` 后访问 http://localhost:3000；开发入口先清理端口。

## 功能

- **录像与分段：** 用户手动开始和停止；支持前后摄像头、自动分段和预览。
- **循环存储：** 按存储配额和素材保留期限清理未保护的旧片段；可保留最近 10、30 或 60 分钟。
- **素材管理：** 浏览、播放、导出、删除本机录像，并恢复部分异常退出留下的素材。
- **时间轴与总结：** 将转写和分析结果关联到原始片段，生成当天工作摘要。
- **可选 AI：** 使用用户自己的 DeepSeek API Key 分析转写文字。AI 默认关闭，原始视频和音频不会发送给 DeepSeek。
- **局域网控制：** 在可信的同一 Wi-Fi 网络中，用电脑浏览器查看时间轴并控制录像。
- **本机优先：** 录像保存在设备本地；无需 EverFrame 云端账号或服务，也不会自动同步。

## 平台与状态

| 平台    | 技术                             | 最低版本              | 状态                                                                               |
| ------- | -------------------------------- | --------------------- | ---------------------------------------------------------------------------------- |
| iOS     | SwiftUI、AVFoundation            | iOS 16                | 正在申请开发者账号，后续计划上架 App Store；摄像头、麦克风和长时间录像仍需实机验收 |
| Android | Kotlin、Jetpack Compose、CameraX | Android 8.0（API 26） | 提供 v0.1.1 预览 APK；录像、音轨、双摄和长时间稳定性仍需实机验收                   |

双摄录制依赖设备支持并发前后摄像头；代码实现不代表所有机型均兼容。Android 系统文件转写是默认关闭的实验功能，设备支持情况和识别服务行为需要单独验证。详见 [Android 说明](android/README.md)。

## 快速开始

### iOS

需要 macOS 和 Xcode。无需 CocoaPods、Docker 或单独的服务器。

1. 在 Xcode 中打开 `EverFrame.xcodeproj`。
2. 在 **Signing & Capabilities** 中选择开发 Team，并设置唯一的 Bundle Identifier。也可以将 `Config/Local.xcconfig.example` 复制为 `Config/Local.xcconfig` 后修改标识符；本地配置不会提交到仓库。
3. 连接 iPhone，选择设备和 `EverFrame` Scheme，运行应用。

最低系统为 iOS 16。iOS Simulator 无法替代真实摄像头、麦克风、温度和长时间录像测试。分步骤安装说明见 [iOS 测试与验收手册](docs/TESTING.md)。

### Android

需要 JDK 17 或兼容的更新版本，以及 Android SDK Platform 36、Build-Tools 35.0.0 和 Platform-Tools。设置 `ANDROID_HOME` 指向 Android SDK。在仓库根目录运行：

```sh
./scripts/android.sh doctor   # 检查 JDK、SDK 和已连接设备
./scripts/android.sh build    # 构建 Debug APK
./scripts/android.sh test     # 运行 JVM 与 TCP 测试
./scripts/android.sh check    # 测试、Lint、Debug 和 Release 构建
./scripts/android.sh install  # 安装到已授权的 USB 真机并启动
```

首次构建时 Gradle Wrapper 需要联网下载 Gradle 和依赖。构建及测试产物默认放在系统临时目录。完整说明见 [Android 开发指南](android/README.md) 和 [Android 真机测试手册](docs/ANDROID_TESTING.md)。

## 本地开发与验证

macOS 上可以运行 iOS 构建和核心测试：

```sh
./scripts/build.sh Debug
./scripts/build.sh Release
./scripts/test-core.sh
./scripts/test-web.sh
```

构建输出和测试夹具使用系统临时目录。HTTP 测试会使用本机 `18080` 端口，运行前会清理该端口上的监听进程。上述命令只能验证构建和可自动化测试覆盖的行为，不能代替实机验收。

## 隐私与安全

- 录像由用户明确开始，默认保存在设备本地；应用没有云端账号或自动上传原始音视频的功能。iOS 切后台／锁屏停录；Android 在前台启动持续录像服务后支持锁屏录像，系统拒绝服务时回退前台录制。
- AI 默认关闭。启用并配置 API Key 后，转写文字和分析所需文字会发送给用户配置的 DeepSeek 服务；请勿输入不适合外发的内容。
- iOS 语音转写优先使用 Apple 设备端识别。若需使用 Apple 在线语音识别，用户必须在系统权限和应用设置中明确允许。
- 局域网电脑控制使用 HTTP 明文，只适合可信的局域网；不要在不可信或公共网络中启用。
- 导出、分享、删除和卸载可能影响本机素材。重要录像请自行导出备份。

详细说明见 [隐私说明](docs/PRIVACY.md)。如发现安全问题，请勿在公开 Issue 中附上 API Key、配对令牌、私人录像或转写内容。

## 项目文档

- [架构说明](docs/ARCHITECTURE.md)
- [录像与分段](docs/RECORDING.md)
- [存储与恢复](docs/STORAGE.md)
- [局域网电脑控制](docs/WEB_CONTROL.md)
- [语音转写](docs/TRANSCRIPTION.md)
- [DeepSeek 配置与分析](docs/DEEPSEEK.md)
- [iOS 测试与验收](docs/TESTING.md)
- [Android 测试与验收](docs/ANDROID_TESTING.md)
- [Android 验证记录](docs/ANDROID_VALIDATION.md)
- [故障排查](docs/TROUBLESHOOTING.md)

## 参与贡献

欢迎通过 GitHub Issues 反馈问题或提交 Pull Request。提交前请：

1. 说明复现步骤、预期结果、实际结果，以及设备型号和系统版本。
2. 运行与改动相关的构建或测试命令，并在 PR 中说明结果；涉及相机、音频或系统服务的改动，请注明实机验证情况。
3. 不要提交 `.env`、签名密钥、个人 Scheme、API Key、设备日志中的隐私信息、录像或真实转写内容。

## 许可证

本项目使用 [MIT License](LICENSE)。
