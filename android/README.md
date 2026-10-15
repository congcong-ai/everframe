# EverFrame Android 原生版

Kotlin、Jetpack Compose、CameraX 实现，最低 Android 8.0（API 26），编译与目标 API 36。与现有 SwiftUI / AVFoundation iOS 版在同一目录维护，不改变 iOS 工程。应用免费、本机优先，基础录像不需要账号、服务器或 AI。

这是需要真机验收的开发版。编译、JVM 测试、Lint 与摄像头长时稳定性是不同层次的证据，本机已通过Debug/Release构建、30项JVM/文件/TCP测试与Lint（0错误、12提示），具体结果见 [验证记录](../docs/ANDROID_VALIDATION.md)。现已在华为 OCE-AN10（用户报告鸿蒙4.2，ADB环境Android12/API31）完成安装与启动检查；录像、音轨、双摄和长时稳定性仍待单独验收。该机API31不满足实验系统文件转写的API34要求，可使用转写JSON导入。

## 一条命令构建、测试、安装

安装 JDK 17 或兼容的更新版本，以及 Android SDK。推荐通过 Android Studio 的 SDK Manager 安装：

- Android SDK Platform 36。
- Android SDK Build-Tools 35.0.0。
- Android SDK Platform-Tools（含 adb）。

将 `ANDROID_HOME` 指向本机 SDK；脚本也会探测 macOS 默认 SDK 路径。首次运行 Gradle Wrapper 会联网下载固定版本 Gradle 和依赖。Wrapper 校验官方 SHA-256，不依赖全局 Gradle。

在仓库根目录执行：

```sh
./scripts/android.sh doctor   # JDK、SDK、adb 设备信息
./scripts/android.sh build    # Debug APK
./scripts/android.sh test     # JVM 规则与真实 TCP 传输测试
./scripts/android.sh check    # 测试、Lint、Debug 和未签名 Release APK
./scripts/android.sh install  # 构建后更新安装到唯一已授权 USB 真机并打开
```

所有编译产物、项目缓存和测试报告默认在 `${TMPDIR:-/tmp}/everframe-android-build/`，不会写入 iOS 工程。可设置 `EVERFRAME_BUILD_DIR` 覆盖。Gradle 下载缓存仍按 Gradle 标准保存在用户目录。Android Studio 也能直接打开 `android/`；从 IDE 运行时同样将模块构建输出放到系统临时目录。

如需指定设备，用 `ANDROID_SERIAL=设备序列号 ./scripts/android.sh install`。安装脚本默认使用 `adb -d`，不会自动选中模拟器。开启开发者选项和 USB 调试，解锁手机确认授权，`doctor` 应显示 `device`；`unauthorized` 或空设备列表均不能安装。Debug APK 为标准开发签名，可在自己的设备侧载。Release APK 尚未配置发行签名，不能直接发布 Google Play。

工具链固定：AGP 8.13.2、Gradle 8.13、Kotlin 2.2.21、Compose BOM 2025.10.00、CameraX 1.6.2。Google Play 当前要求新应用/更新面向 API 36；提交前应再核对[官方目标 API 要求](https://developer.android.com/google/play/requirements/target-sdk)。CameraX 版本依据[官方发布记录](https://developer.android.com/jetpack/androidx/releases/camera)。

## 使用

1. 进入“记录”，点击开始或开启取景，允许摄像头和麦克风权限。只开启取景不会写文件。拒绝后可在“设置 → 打开系统权限设置”重新开启。
2. 开始后保持前台，屏幕保持亮起。停止后等“正在保存”结束，再到“素材”播放，确认音画正常；导出到系统文件选择器选定的位置。
3. 默认后置单镜头，优先 720p，不支持时由 CameraX 选择兼容质量。文件为 MP4；实际尺寸、编码、帧率由设备协商，封装后读取真实值，无法读取的帧率记为未知（0），不伪称固定24fps。前置文件不镜像；预览镜像、方向需真机检查。
4. 默认每10分钟自动停止封装并开始新段，可选5/10/15/30分钟；单文件接近3.8GB也会提前分段。分段可能存在短暂音画间隔。切换镜头/双录前必须先停止保存，Android 首版暂不提供录像中自动切镜头续录。
5. 保留最近10/30/60分钟会保护与窗口相交的整段，包括当前段的持久化 pendingLock。当前段结束后转换为 locked，保护时长可能超过所选窗口，不能找回已经删除的录像。
6. 默认40GB配额、7天普通素材、尽量保持15GB剩余空间。按最老优先清理未保护段；写入中、等待保护、已保护、分析/播放/导出中素材不参与循环清理。保护素材过多时可能无法达到配额；绝不为腾空间强删保护文件。实际可用低于1GB时停止。小容量设备可在设置调整目标剩余空间。
7. 离开前台、锁屏或摄像头/音频中断会停止并尽力封装，返回后必须手动开始。没有后台录像服务，也不会后台自动恢复录像。系统强杀或断电仍可能导致文件损坏，恢复时保留并保护原文件，不能保证可播放。
8. 素材页支持保留/取消、播放、导出、删除确认、导入转写和重试分析。删除会删除本机视频与关联转写/分析；每日总结作为历史快照保留。卸载会删除所有私有数据，重要素材务必导出。系统备份已关闭。

## 电脑控制

设置中开启后，前台连接可信 Wi-Fi，页面显示 `http://局域网地址:8080` 和六位配对码。与电脑连接同一 Wi-Fi，浏览器打开地址并配对。Android 直接打包现有 `EverFrame/Web/` 资源；共同 API 见 [协议](../shared/README.md)。没有增加互联网服务、端口转发或云同步。

监听绑定实际 Wi-Fi IPv4 地址，匿名 API 返回401，配对五次失败冷却一分钟，最多八个会话、12小时过期；每次重开/切后台会清空会话。修改请求检查 JSON、Host 与 Origin；HTTP 头16KB、正文64KB、有限连接队列和超时。不在日志或网页返回 API Key、视频或完整转写。

这是局域网 HTTP，配对码和令牌不具备传输加密，不能抵抗恶意网络旁观者；只应在可信 Wi-Fi 使用。关闭、后台或 critical 温度会停止监听。Android未来版本局域网权限变化、厂商网络隔离需要实机确认。端口被占用时明确报错，不会终止手机上其它应用。

## 转写与 AI

AI 默认关闭。用户输入自己的 DeepSeek API Key，Android Keystore 生成 AES-GCM 密钥加密保存；禁用系统备份，源码不含开发者密钥。密钥保存后输入框清空，不回显。仅测试连接会发送小型测试提示。启用 AI 时明确同意转写文字和片段摘要发送 DeepSeek，不发送原始音视频。模型可在手机设置更改。

Android 不能复用 Apple Speech。官方 `EXTRA_AUDIO_SOURCE` 从 API33 支持 PCM 文件，但服务可能忽略该功能并改开麦克风；词级时间戳从 API34 提供，也依赖识别服务。`isOnDeviceRecognitionAvailable` 只证明端侧服务存在，不证明离线中文、文件输入和时间戳全部可用。因此系统文件转写是**默认关闭、尚待真机验证的实验功能**，不能宣称所有 Android 手机均可转写。

实验实现仅创建端侧 SpeechRecognizer，检查已安装中文模型，将录像音轨通过 MediaCodec 解码为16位PCM，按55秒块串行提供文件描述符，并请求词级时间戳；每块完成后加回原录像偏移。时间区间的结束值取下一个词的开始，最后一个词取块末尾，这是展示区间，不是服务提供的精确词尾。若模型、文件或时间戳不支持、识别为空、超时，则明确失败，不生成假内容，不切在线识别。

**即使检查通过，仍须用真机“文件说A、环境说B”对照测试，证明厂商服务确实消费文件。** 系统API无法单靠能力查询证明文件输入未被忽略；在验收前不要对隐私敏感环境启用该实验选项。没有适用服务时，保持它关闭，使用素材页“导入转写”。这条限制是未解决的设备能力验收项。

导入格式见 [中文样例](../shared/fixtures/transcript.zh-CN.json)，`clipID` 必须改成对应素材UUID（导出默认文件名中可见），时间相对原录像秒数，语言 `zh-CN`，必须非空、顺序正确且在实际时长内，最大2MB。导入后可以直接走 DeepSeek 分析链路，不依赖系统语音服务。

分析按片段串行，仅完成且通过音视频校验的录像可进入队列。默认只在前台待机、Wi-Fi、充电、温度正常时运行，开始录像会暂停；下次满足条件继续。失败标记后等待手机手动重试，避免无限重试消耗余额。AI严格校验分数、时间范围和每日总结引用，网络/解析错误不影响录像。时间轴点击可定位原片段；今日总结只依据当天已有分析。

参考：[RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent)、[SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)、[RecognitionPart](https://developer.android.com/reference/android/speech/RecognitionPart)。

## 双摄

默认单镜头，每次启动恢复单镜头。双录前检查 CameraX `availableConcurrentCameraInfos` 中是否确有前/后组合，再通过同一 Preview + VideoCapture 和两个 CompositionSettings 绑定合成。目标为后置上半、前置下半、一个有声MP4，预览与文件均需独立核验画面比例、裁切、方向、同步和音轨。设备暴露并发组合并不保证具体画幅和编码负荷能绑定成功；失败明确提示并切回单镜头，用户重新开始。

实现依据 [CameraX 配置](https://developer.android.com/media/camera/camerax/configuration) 与 [CompositionSettings](https://developer.android.com/reference/androidx/camera/core/CompositionSettings)。目前没有兼容真机，**不能视为双录已验收**，也不承诺所有 Android 手机支持。

## 架构与状态

- `RecordingController`：主线程串行协调 CameraX，状态 `RECOVERING → IDLE → PREPARING → RECORDING → FINALIZING → IDLE/ERROR`。分段续录意图独立保存，手动停止、后台、中断、低空间优先取消；不会因迟到的 Finalize 回调重新开始。
- `ClipRepository`：原子逐段JSON、MP4索引、真实音视频检查、循环策略、保护、恢复。开始录像先写索引；封装后重新读取最新 pendingLock。解析失败原文件仍保留。
- `AppModel`：生命周期、温度、设置、网络和串行分析；无服务器依赖。severe暂停分析，critical再停电脑控制，emergency停录像；系统也可能更早停止摄像头。
- `LocalWebServer`：有限HTTP解析、配对与实际TCP，控制请求派发主线程，超时取消。网页资源复用iOS目录。
- `AndroidTranscription` / `DeepSeek` / `APIKeyStore`：实验端侧文件转写、可选文字分析、设备密钥保护。
- `MainActivity`：Material 3四页，切页时保持取景Surface存活，避免重绑正在写入的摄像头。停止按钮在准备和保存状态仍可取消续录。

长时间无录像状态更新、启动超时、音频静音/错误均请求安全停止。保存超过20秒会告警并取消续录，保留写入对象等待设备返回，避免尚未释放时并发创建新段；如系统不返回，只能下次启动恢复检查。不会承诺强杀恢复所有帧。

## 真机验收

完整操作见 [Android 测试手册](../docs/ANDROID_TESTING.md)。至少需要一台普通手机和一台实际支持前后并发的手机。按“一分钟单摄有声 → 短分段 → 循环保护 → 中断恢复 → Web → 转写对照 → AI → 双摄 → 2/4/8小时”的顺序，不得用APK构建成功替代。

开源前检查 `.env`、`local.properties`、签名密钥、日志、设备序列号、录像和转写内容。当前 applicationId 为开发占位，正式上架前确定唯一标识和发行签名；不将个人签名材料提交。现有 Gradle Wrapper 版权声明保留。项目开源许可证尚未选择，此次不新增项目许可证。未发布商店、未创建PR、未操作GitHub。
