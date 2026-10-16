# EverFrame

**让用户负责工作，让 EverFrame 负责记住。**

EverFrame 是一款本机优先的原生录像与工作时间轴应用，适用于 iPhone 和 Android。它支持手动录像、自动分段、循环存储、片段保护与导出；也可以选择转写、AI 分析和局域网电脑控制。

项目仍在开发中。编译通过不代表相机、麦克风、音轨、双摄或长时间录像已通过所有设备的实机验收。使用前请阅读下方的已知限制和对应平台测试手册。

**Android：** [下载 v0.1.1 APK（预览版）](https://github.com/congcong-ai/everframe/releases/download/v0.1.1/everframe-android-v0.1.1-debug.apk)。这是用于直接安装体验的开发签名版本。

**iOS：** 正在申请 Apple Developer Program 开发者账号，后续计划上架 App Store。

本地安装包统一放在 [`artifacts/`](artifacts/README.md)，运行 `./scripts/package.sh` 可重新生成；二进制不进入 Git，Android APK 通过 GitHub Releases 下载。

## 功能

- **录像与分段：** 用户手动开始和停止；支持前后摄像头、自动分段和预览。
- **循环存储：** 按存储配额和素材保留期限清理未保护的旧片段；可保留最近 10、30 或 60 分钟。
- **素材管理：** 浏览、播放、导出、删除本机录像，并恢复部分异常退出留下的素材。
- **时间轴与总结：** 将转写和分析结果关联到原始片段，生成当天工作摘要。
- **可选 AI：** 使用用户自己的 DeepSeek API Key 分析转写文字。AI 默认关闭，原始视频和音频不会发送给 DeepSeek。
- **局域网控制：** 在可信的同一 Wi-Fi 网络中，用电脑浏览器查看时间轴并控制录像。
- **本机优先：** 录像保存在设备本地；无需 EverFrame 云端账号或服务，也不会自动同步。

## 平台与状态

| 平台 | 技术 | 最低版本 | 状态 |
| --- | --- | --- | --- |
| iOS | SwiftUI、AVFoundation | iOS 16 | 正在申请开发者账号，后续计划上架 App Store；摄像头、麦克风和长时间录像仍需实机验收 |
| Android | Kotlin、Jetpack Compose、CameraX | Android 8.0（API 26） | 提供 v0.1.0 预览 APK；录像、音轨、双摄和长时间稳定性仍需实机验收 |

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
