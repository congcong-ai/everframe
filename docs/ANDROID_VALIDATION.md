# Android 实施与验证记录

日期：2026-10-15（中国标准时间）。本记录只写实际执行证据，硬件未执行项保持待验收。

## 实现边界

保留原SwiftUI/AVFoundation工程，新增独立Android原生工程、单命令构建/测试/安装、四页Compose界面、单摄有声分段、循环保护、低空间停止、播放导出、异常恢复、局域网配对与复用网页、Keystore、可选DeepSeek分析/时间轴/每日总结、并发摄像头能力检查与合成管线。

Android暂不支持录制中无缝切镜头；切换前需要停止保存。系统文件转写默认关闭，属于需要真机验证离线中文/文件输入/词级时间戳的实验能力；同时提供严格校验的转写JSON导入。没有把Apple Speech冒充跨端能力，没有新增账号、云同步、订阅、Docker、后端或项目许可证。

## 环境与工具

- macOS Intel，初始只有Oracle JDK19.0.1，无Android SDK/Gradle/adb。
- 下载Google官方命令行工具，安装API36平台、Build-Tools35.0.0、Platform-Tools，已移动到macOS默认SDK目录。Gradle分发已进入标准Wrapper缓存，后续构建不依赖临时下载目录。
- Gradle8.13官方分发跳转遇到网络连接失败，使用镜像获取，并与官方SHA-256核对：`20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78`。
- Gradle Wrapper源码/JAR保留上游声明与校验配置，项目不依赖全局Gradle。
- 首轮构建时`adb devices -l`为空；随后已连接并授权华为OCE-AN10真机（用户报告HarmonyOS4.2），ADB兼容环境为Android12/API31，支持arm64-v8a。设备序列号不写入文档。
- 当前目录尚无`.git`，无法执行git diff/status；未初始化仓库或执行GitHub写操作。

## 已执行

- `./scripts/test-core.sh`：原iOS核心49项断言通过，包含真实MOV孤立文件恢复与损坏文件保护。
- `./scripts/test-web.sh`：原iOS真实HTTP、匿名拒绝、配对、认证读写、会话撤销五类检查通过。
- `EVERFRAME_BUILD_DIR=/tmp/everframe-android-build ./scripts/android.sh check`：最终完整检查成功，包含Debug/Release代码编译、APK封包、JVM测试、Debug Lint及Release必要Lint。工具迁移后曾因旧编译进程缓存SDK临时路径导致重编译失败；已停止旧进程并执行clean，再从标准SDK路径干净重建成功。最终代码再次完整检查成功（1分49秒）。
- 30项Android测试全部通过：核心规则13、真实临时文件仓库8、共享中文协议1、HTTP解析与配对7、真实TCP碎片传输与端口释放1。文件仓库测试注入媒体检查结果，**不代表Android真实MP4封装已验证**。
- Lint：0错误、12个warning。包括固定工具/依赖版本更新提示、竖屏/大屏适配提示、保守使用实际可用空间的建议、图标与KTX风格建议。未建立baseline隐藏错误。API34调用和录音权限检查已补齐；Android12+云备份/设备迁移明确排除私有数据。Android13+另有单色图标资源，基础图标仍触发Lint建议。
- Debug APK通过`apksigner verify --verbose`（v2开发签名），最低API26、目标API36，所需权限为摄像头、麦克风、网络和网络状态，没有后台录像或广泛存储权限。
- Debug和未签名Release APK均通过`zipalign -c -P 16 4`；二者中arm64-v8a/x86_64共6个原生库的所有ELF PT_LOAD段均为16384字节对齐。未安装NDK，构建保留上游原生库调试符号的提示不影响此次封包/对齐验证；不以此替代16KB系统设备安装测试。
- 两个APK的`assets/index.html`、`app.js`、`style.css`与既有iOS网页资源逐字节一致。
- 后续真机安装：`adb install -r`返回Success；确认`com.everframe.app`已安装、进程存在、MainActivity在前台，已读取四页界面。摄像头/麦克风权限均为granted；未发现该进程的启动崩溃。当前还没有生成录像文件，不能将安装/启动成功等同录像通过。
- 华为OCE-AN10提供API31，低于实验系统文件转写所需API34；该设备不走这套系统转写实现，可使用已实现的转写JSON导入。双摄需要另行运行时验证，厂商能力标签不能代替CameraX绑定和实际合成测试。

## 构建产物与报告

本轮设置`EVERFRAME_BUILD_DIR=/tmp/everframe-android-build`：

| 产物 | 位置 | 大小 |
| --- | --- | --- |
| 开发签名安装包 | `/tmp/everframe-android-build/app/outputs/apk/debug/app-debug.apk` | 23,036,223字节 |
| 未签名Release包 | `/tmp/everframe-android-build/app/outputs/apk/release/app-release-unsigned.apk` | 16,282,331字节 |
| JVM测试报告 | `/tmp/everframe-android-build/app/reports/tests/testDebugUnitTest/index.html` | 30项通过 |
| Lint报告 | `/tmp/everframe-android-build/app/reports/lint-results-debug.html` | 0错误、12提示 |
| 最终完整构建日志 | `/tmp/everframe-android-verified.log` | BUILD SUCCESSFUL |
| 包校验明细 | `/tmp/everframe-android-verification.json` | SHA-256、测试数、原生对齐与共享资源 |

Debug SHA-256：`93acfddb25a730d1d62472e1c08a5a3244c9d425ecb9e0fa3678307a268a2c7e`。

Release SHA-256：`b6a4adde591074ce7d961d9e1e1107a784179c8c4fb22f15dfef547ae82ae652`。

临时目录可能被系统清理；重新构建以脚本输出路径为准。Release没有发行签名，不能当作商店发布包。

## 真机进度

2026-10-15已完成华为OCE-AN10安装、启动、四页基本导航及摄像头/麦克风授权检查。等待用户录制10至20秒并停止后，继续通过真实MP4、ffprobe和解码结果验证基础录像闭环。仅复制本App测试文件到本机临时目录，不提交录像、设备序列号或个人内容。

## 未通过真机验收

以下均为 **待真机验收**，不因构建通过而改变：

- 权限拒绝/恢复、真实摄像头与麦克风、前后镜头、方向/镜像、有声MP4封装、实际分段间隙。
- 播放、系统文件选择器导出、异常强杀后文件可播放性、低空间与温度反馈。
- 真机Wi-Fi监听、配对、前后台网络关闭、不同厂商网络限制。
- 系统端侧识别是否真正读取文件、离线中文模型、55秒块偏移与词级时间戳。
- 用户真实Key的DeepSeek连接/额度/模型以及真实转写分析；未使用任何开发者密钥。
- 并发双摄上下画面合成的比例、裁切、方向、音轨、同步、热负荷与失败降级。
- 2/4/8小时录像稳定性、来电、锁屏、摄像头占用和厂商节电策略。

详细执行步骤见 [Android测试手册](ANDROID_TESTING.md)。未发布Google Play/App Store、未创建PR、未选择开源许可证、未增加发行签名。
