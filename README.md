# EverFrame

现已新增 [Android 原生工程](android/README.md)（Kotlin + Jetpack Compose + CameraX），与现有 iOS 工程同目录维护。Android 构建/测试/安装入口为 `./scripts/android.sh`；硬件功能仍需[独立真机验收](docs/ANDROID_TESTING.md)，不以编译通过代替。原有 iOS 目录和下方安装说明保持适用。

让用户负责工作，让 EverFrame 负责记住。原生 SwiftUI 工作录像与 AI 工作时间轴工具，最低 iOS 16.0，目标真机为 iPhone 8 Plus / iOS 16.7.16。

已经写入录像、自动分段、循环存储、保留最近 10／30／60 分钟、素材播放与导出、局域网配对控制、Apple Speech 转写、DeepSeek 片段分析和每日总结。**这些是可编译实现，不代表已经通过真机验收。** 用户已在 iPhone 上安装并打开初版；新版录制中切换、双录、音轨与长时间录像仍待真机验收。每阶段证据与待测项见 [开发记录](docs/DEVELOPMENT_LOG.md)。

## 从零安装到你的 iPhone

1. 安装并打开 Xcode。本项目优先使用真实 iPhone，不需要先下载 iOS 16.x Simulator。Components 中明确写着 Simulator 的项目只用于 Mac 模拟设备；连接真机后，如 Xcode 另外提示缺少设备／平台支持，再按该提示安装。双击仓库中的 `EverFrame.xcodeproj`，不要只打开某个 Swift 文件。不需要 CocoaPods、第三方包、Docker 或服务器。
2. 在 **Xcode → Settings → Accounts** 点 `+`，用普通 Apple Account 登录。未加入付费开发者计划时，Xcode 会显示 **Personal Team**，它用于把自己的开发版 App 安装到自己的设备。
3. 点击左侧蓝色项目图标 → **TARGETS → EverFrame → Signing & Capabilities**。勾选 **Automatically manage signing**，Team 选择你的 Personal Team。不需要添加任何付费能力。
4. 配置唯一 **Bundle Identifier**，例如 `com.你的英文名.everframe`。默认 `com.example.everframe` 只是占位。建议将 `Config/Local.xcconfig.example` 复制为 `Config/Local.xcconfig` 后修改 `PRODUCT_BUNDLE_IDENTIFIER`；本地文件不会被提交。也可以在 Xcode 中编辑。产品名和显示名集中在 `Config/Product.xcconfig`；数据目录名称固定，改显示名不会把旧录像藏起来。
5. 用数据线把 iPhone 连接 Mac。解锁手机，在手机选择“信任此电脑”，输入密码。首次先用有线连接，避免无线配对干扰排错。
6. iOS 16 如要求开发者模式：手机 **设置 → 隐私与安全性 → 开发者模式**，开启并按提示重启、再次确认。若菜单还没出现，先让 Xcode 识别连接的设备并尝试运行。个人签名如提示不受信任，在 **设置 → 通用 → VPN 与设备管理** 信任自己的开发者身份。
7. 在 Xcode 顶部选择 **EverFrame** Scheme，运行设备选择你的 **iPhone 8 Plus**。Deployment Target 保持 **16.0**。如显示设备不可用，先看 `Window → Devices and Simulators` 的具体提示，完成设备支持组件下载。
8. 点击 `▶` 或按 `⌘R`，等编译、签名和安装完成。不要把命令行生成的未签名 `.app` 当成可直接安装包。顶部如出现 “iOS 26.5 Not Installed / Get”，先连接真实 iPhone，再点顶部运行目标下拉菜单选择该手机。没有安装模拟器 runtime 时也可能显示 Get，不能仅凭此提示判断真机支持缺失；若真机仍不可选，再看 Devices and Simulators 中具体原因。无需升级手机系统或修改最低系统。
9. 首次进入“记录”，摆稳手机并接通电源。**点击“开始记录”或摄像头切换按钮后**，依次允许 Camera／Microphone。切换按钮可以先打开取景预览，但只有点击“开始记录”才会写入录像。拒绝后可去系统设置的 App 权限里重新开启。开始前不会自动录像；录像中持续显示红色 **REC · 正在记录**。
10. 点击“停止记录”，等待保存完成。进入“素材”播放，确认画面和声音都有。点击分享按钮可以保存至“文件”、AirDrop 到 Mac 等。删除已保留素材会再次确认。
11. 需要转写时，到“设置”点击 **授权 Apple 语音识别**，允许 Speech 权限。App 优先本地中文识别；A11／中文本地识别是否可用必须实测。默认不会在线发送音频。若提示本地不支持，可主动开启“允许 Apple 在线语音识别”，阅读确认后再同意；系统可能限流。
12. 在“设置 → AI”输入自己的 **DeepSeek API Key** 并保存，填入的内容随后清空，不回显。Key 保存在 **Keychain**，不会进入源码、JSON、UserDefaults 或日志。开启 AI 后点“测试连接”，成功后接通电源并保持 Wi-Fi。默认自动分析只在 Wi-Fi 且充电时执行；已有完成片段会排队，不分析正在写入的片段。AI 是可选开关，默认关闭，未配置 Key 仍可完整录像。
13. 开启“电脑控制”，出现 Local Network 弹窗时允许。手机、电脑连接同一可信 Wi-Fi。设置页会显示 `http://手机IP:8080`、二维码和六位配对码；电脑浏览器输入该网址并输入配对码。二维码仅包含网址，配对码需另行输入。支持开始、停止、保留最近、查看素材、保留／取消保留、今日时间轴和生成今日总结。播放、删除和导出在手机操作。
14. 录像必须保持 App 前台。手动调低系统亮度，保持 REC 可见，不锁屏；切后台会停止并尽力完成当前文件。系统可能在电话、锁屏、摄像头占用或温度情况下中断录像，恢复前台后需要手动重新开始。
15. “设置 → 查看诊断日志”可以查看事件；“导出诊断日志”可以分享。Xcode 底部 Console 也会显示日志。日志不包含 Key、令牌、完整转写和 AI 原文。Finder → iPhone → 文件 → 本 App，可备份 Documents；录像目录排除系统自动备份，**重要素材请手动导出**。不要靠卸载重装排错，卸载会丢失本机录像。
16. 免费 Personal Team 的开发 provisioning profile **签发后 7 天过期**，需要再连接 Xcode 重新 Build & Run。保留相同 Bundle Identifier 和签名身份，更新安装；不要先卸载。免费账号还有 App／设备数量限制，详见 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。未来上架再处理付费 Developer Program 与 Distribution。

## Xcode 要求下载大型模拟器时的替代安装方式

如果已经选中真实 iPhone，但 Xcode 的 Run 仍要求下载模拟器，可以尝试先直接构建 target，再安装已签名包。需要先在 Xcode 配置自己的 Personal Team、唯一 Bundle Identifier，并取得包含自己设备的有效 provisioning profile。

```sh
xcodebuild -project EverFrame.xcodeproj -target EverFrame \
  -configuration Debug -sdk iphoneos -arch arm64 \
  SYMROOT=/tmp/everframe-device-install build
```

此命令与 `scripts/build.sh` 不同：不关闭签名。只有构建成功、App 内包含有效 embedded.mobileprovision、签名通过校验且 profile 包含目标设备后，才能把 App 放入 Payload 目录打成 IPA。不要将未签名构建直接改后缀当安装包。

在 Xcode → Window → Devices and Simulators → Devices 选择真实 iPhone，点击 Installed Apps 下方的 `+`，选择已签名 IPA 安装；不是左侧设备列表下方的 `+`。安装后从手机主屏幕手动打开。若系统提示，启用开发者模式或信任自己的开发者身份。此路径只解决安装，不代替 Xcode Run 的调试能力，也不证明录像已通过真机验收。

安装操作参考 [Apple 设备安装说明](https://help.apple.com/xcode/mac/current/en.lproj/devade83d1d7.html)。Personal Team 包仍会周期性过期，不应分享给其它设备或公开发布。

## 记录页操作

- 记录页以摄像头取景为主，不再展示大产品标题与口号；上方常驻 REC／待机及连续记录计时，底部固定开始／停止与切换镜头按钮，无需滚动寻找停止按钮。四个 Tab 保持不变。
- 点击右侧摄像头按钮在前置／后置间切换，录制中也可操作：先完成当前片段并保存，再切换镜头、自动开始下一段，连续计时不重置。切换处可能有短暂音画间隔，不承诺无缝或同一个文件。切换期间禁止重复操作，但停止按钮仍可用；停止、切后台、中断或低磁盘会取消自动续录。
- 前置取景预览镜像，保存的录像不镜像；App 保持竖屏，前后镜头均重新配置方向、可用预设及编码，24fps 仅在当前格式支持时设置。切换保留麦克风输入；录制中切换失败时确认原镜头可用后自动恢复录制，无法恢复则明确停止并保留原文件。
- 点击底部“保留最近”，选择 10／30／60 分钟；成功提示直接显示在取景区域。右上角“…”打开记录详情，可查看占用、剩余空间、今日累计、AI 进度与值得回看的片段。
- 磁盘、温度与录像中断的警告摘要始终显示在记录页顶部；轻点可读完整信息，不会被折叠到详情里，也不会被保留成功提示覆盖。
- 控制区适配安全区域与动态字体；iPhone 8 Plus、最大辅助字体、镜像及实际画面仍需真机检查，不能以构建通过替代。

记录页右上角新增“双录”按钮，详情页也可操作。支持设备可在停止保存后选择双录，再点击开始：上半屏后置、下半屏前置，合成为一个720×1280／24fps目标、有声MOV（H.264／AAC），支持原有自动分段与保留；预览和文件均不镜像。上下画面为等比裁切填充。双录会增加功耗和发热，当前会话切回单镜头前需停止保存，重启App默认单镜头。

不支持设备点击“双录”会明确提示本机不支持及兼容代际，不改变当前录像，也不请求权限。iPhone 8 Plus 不支持前后同时采集。通常需要 iPhone XS／XS Max／XR 或更新的兼容机型，并非所有后续型号都支持；App实际检查 `isMultiCamSupported` 与前后广角摄像头组合，启动时还检查格式和设备负荷。参考 [Apple MultiCam 官方说明](https://developer.apple.com/videos/play/wwdc2019/249/)。双录管线已实现并通过编译及合成CLI检查，但当前没有兼容真机，**实际双录、音轨与稳定性仍为 NEEDS PHYSICAL DEVICE TEST**。

## 默认行为

- 默认单镜头后置、720p、24fps、麦克风开启；单镜头 MovieFileOutput 优先 HEVC，不支持则 H.264；MOV 默认音轨为 AAC，必须在真机检查实际文件。
- 每段 10 分钟，可选 5／10／15／30；切镜头会提前结束当前段并新建下一段。切段允许短暂间隔，不承诺零帧丢失。
- 录像最多 40 GB，普通素材 7 天，尽量保持系统剩余 15 GB。任一触发即清理最老未保护片段；当前、pendingLock、locked 和分析中的文件不删除。实际可用空间低于 1 GB 时安全停止。保护素材过多时不会强行删除它们。
- 保留操作保护与时间窗口相交的整个片段，可能比所选 10／30／60 分钟更长。不会恢复已经被循环删除的文件；当前段立即保存 pendingLock，封装后锁定。
- 语音转写按 55 秒音频块串行执行，再加回原片段秒偏移；识别失败不伪造内容。DeepSeek 仅接收带时间戳文字，输出中文摘要、时间轴、主题、观点、分数和回看原因。
- serious 暂停 Speech／AI；critical 还暂停电脑控制。录像尽可能继续，但系统仍有权中断摄像头。
- 无账号、云同步、NAS、视频剪辑、订阅、后台录像或互联网远程控制。

## 开发与验证

```sh
# 仅在确需新增源文件且已备份手工签名配置时才重新生成工程。
# 生成器会覆盖 project.pbxproj；工程已登记全部源文件，无需执行。
# python3 scripts/generate-project.py

# 未签名 iPhone arm64 编译，不安装、不访问开发者网站。
./scripts/build.sh Debug
./scripts/build.sh Release

# macOS CLI：存储、保护、JSON、真实 MOV 恢复测试。
./scripts/test-core.sh

# 真实 NWListener HTTP 传输和配对测试，先清理 18080 监听端口。
./scripts/test-web.sh
```

构建输出与测试夹具位于系统临时目录，不写进源码目录。本项目直接提交 `.xcodeproj`，用户不需要运行生成器才能打开。签名设置请保存到 `Local.xcconfig`，因为重新生成工程会覆盖 Xcode 工程中的手工修改。

Debug 才显示“开发者设置”：30 秒／1 分钟分段、300 MB 配额、模拟低磁盘、强制 AI、查看 AI JSON。测试设置不持久化，重启恢复正常；强制 AI 仍受 AI 启用、温度、前台和 Key 限制。Release 中不显示这些选项。

若要用开发环境变量：Xcode → Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables 添加 `DEEPSEEK_API_KEY`。仅 Debug 读取，不自动读取 `.env`；不要提交个人 Scheme 或真实 Key。正式使用在 App 设置录入。

**Simulator 不能等价验证真实摄像头、麦克风、长时间录像、温度和磁盘循环。** 当前机器没有已安装的模拟器 runtime。真机测试按 [测试手册](docs/TESTING.md) 分阶段完成；不能以编译通过取代验收。

## 文档

[架构](docs/ARCHITECTURE.md) · [录像](docs/RECORDING.md) · [存储](docs/STORAGE.md) · [电脑控制](docs/WEB_CONTROL.md) · [转写](docs/TRANSCRIPTION.md) · [DeepSeek](docs/DEEPSEEK.md) · [隐私](docs/PRIVACY.md) · [上架准备](docs/APP_STORE.md) · [测试](docs/TESTING.md) · [排错](docs/TROUBLESHOOTING.md) · [开发记录](docs/DEVELOPMENT_LOG.md)

本项目尚未选择开源 License；未获得明确许可前不应自行假定代码已经开源授权。
