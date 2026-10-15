# 开发记录

日期：2026-10-15。起始目录为空，未初始化 Git；本轮没有远端写操作。工具：Xcode 26.5（17F42）、Swift 6.3.2，项目使用 Swift 5 模式、iOS 16.0 deployment target，arm64。

**验收口径：下面“已实现”表示源码已写入且通过构建，不表示真实 iPhone 测试通过。** 本轮未连接 iPhone；没有真实 DeepSeek Key；本机无模拟器 runtime。严格保留所有硬件验收项，不将实现量代替稳定性证据。

## Phase 1 — 摄像头

Completed:
- 已实现 SwiftUI Preview、按用户点击请求摄像头／麦克风、开始／停止、MOV 保存及原文件播放。
- 已实现 REC、禁止自动锁屏、停止后恢复、进入后台停止、摄像头／音频中断处理。

Build:
- PASS：直接 target 的 Debug arm64 编译链接。初始工程生成器的空资源列表语法问题已修复。

Simulator:
- NOT TESTED：无已安装 runtime，且不能替代摄像头验收。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- 未验收真实音轨、HEVC／H.264 结果、设备权限和 Personal Team 安装。

Next:
- 按 TESTING.md 在 iPhone 8 Plus 上完成开始／停止／播放／有声测试。

## Phase 2 — 自动分段

Completed:
- 已实现 RecordingEngine 抽象、MovieFileOutput 时长上限分段、封装后续录、实际 metadata、非正常结束保留原文件。
- Debug 30 秒／1 分钟；生产默认保持 10 分钟，支持 5／10／15／30。
- 停止与启动竞争有串行队列与取消标记，避免停止指令在配置期间失效。

Build:
- PASS：已并入最终 Debug／Release 构建。

Simulator:
- NOT TESTED。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- 没有连续录十分钟；约十个文件、全部有声、全部可播放和切段间隔待测。

Next:
- Debug 选 1 分钟录十分钟，逐一检查后恢复正常时长。

## Phase 3 — 循环存储

Completed:
- 已实现 40 GB／7 天／15 GB 默认政策、最旧优先清理、当前／locked／pendingLock／分析占用排除。
- 1 GB 危险阈值、500 MB MovieFileOutput 底线、配额不足提示。
- 300 MB／模拟低磁盘 Debug 控件；metadata 原子保存，缺失索引和损坏 MOV 恢复。

Build:
- PASS。

Simulator:
- NOT TESTED；macOS CLI 的实际文件与恢复测试 PASS。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- 真实设备循环覆盖、空间读数、低磁盘停止和强杀中的 MOV 可恢复性未实测。

Next:
- 使用无私人内容的测试素材在手机执行 300 MB 清理验收。

## Phase 4 — 保留最近

Completed:
- 已实现 10／30／60 分钟窗口相交保护、当前 pendingLock、封装重新读取保护标记、锁定与取消锁定。
- CLI 验证跨片段、边界相交、重载保护状态、禁止当前删除和锁定确认。

Build:
- PASS。

Simulator:
- NOT TESTED；macOS CLI PASS。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- 当前真实录像分段切换瞬间点击保留仍需设备回归。

Next:
- 在真实跨段录像中操作三种窗口并重启检查 JSON。

## Phase 5 — 电脑控制

Completed:
- 已实现 NWListener、有限 HTTP Parser、网页、二维码、配对、随机令牌、认证读写、失败限流、会话撤销。
- 已实现要求的 status／start／stop／keep／clips／lock／unlock／timeline／daily-summary／settings 接口。
- 实际 NWListener + URLSession 传输测试通过；业务状态使用夹具，未冒充 iPhone WebAPI 验收。

Build:
- PASS；网页 JavaScript 语法检查 PASS。

Simulator:
- NOT TESTED；Mac HTTP 传输与配对检查 5 项 PASS。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- 手机本地网络权限、实际 Wi-Fi 地址与电脑浏览器端到端尚未验证。
- HTTP 明文只适合可信局域网；没有 snapshot／实时视频能力。

Next:
- 按 WEB_CONTROL.md 用真实手机地址配对，验证控制及重新配对撤销。

## Phase 6 — 语音

Completed:
- 已实现 AppleSpeechTranscriptionProvider、zh-CN、55 秒 M4A 分块、带秒偏移的 transcript、本地优先、在线单独同意。
- 已实现串行、超时、单次 continuation 完成和任务取消。

Build:
- PASS。

Simulator:
- NOT TESTED；transcript 持久化与关键词检索 CLI PASS。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- A11 本地中文支持、Apple 在线限流、1／10 分钟实际识别质量与时间戳待测。

Next:
- 先一分钟已知内容，再十分钟内容，检查 55 秒块边界。

## Phase 7 — DeepSeek

Completed:
- 已核对官方文档；集中模型与 HTTPS endpoint、Keychain、测试连接、片段分析、fence 兼容、字段与时间校验、失败重试。
- 模型 JSON 解析和越界拒绝 CLI PASS。

Build:
- PASS。

Simulator:
- NOT TESTED；未使用真实 Key 或消耗 API 费用。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- DeepSeek 真实 HTTP、账号模型权限、计费、摘要效果未联调；不能承诺输出质量。

Next:
- 用户在手机输入 Key，完成连接与单片段验收。

## Phase 8 — 每日总结

Completed:
- 已实现仅以当天片段摘要为输入、严格结构解析、真实 UUID 引用校验、本地保存和时间轴展示。
- 已实现历史日期查看、主题／转写／观点／摘要搜索、回看建议跳转原片段。

Build:
- PASS。

Simulator:
- NOT TESTED。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST。

Known Issues:
- 真实多片段 DeepSeek 每日总结未执行；保存的每日总结与片段删除是独立语义。

Next:
- 至少三段真实已完成 AI 分析后生成总结，重启检查持久化。

## Phase 9 — 稳定性

Completed:
- 已实现 thermalState 监控、serious 暂停分析、critical 关闭电脑控制、原始录像隔离、有限后台封装和滚动事件日志。
- 完成可重复构建脚本、CLI 测试、初学者 README 与全部专题文档。

Build:
- PASS：最终 Debug、Release 均为未签名 arm64；最低系统 iOS 16.0。不是安装包验收。

Simulator:
- NOT TESTED：未安装 runtime，无 UI 截图和真实运行证据。

Physical Device:
- NOT TESTED — NEEDS PHYSICAL DEVICE TEST；2／4／8 小时测试全部未执行。

Known Issues:
- Xcode Scheme 枚举曾显示 iOS 26.5 未安装；直接 target 编译可行。当时未连接手机且无模拟器 runtime，不能仅据此认定真机支持缺失；应连接设备、选择真机并根据具体提示处理签名或组件。
- App 图标尚未作为正式素材加入：本机 asset catalog 编译需要缺失的 simulator runtime；不让非核心图标阻塞源码与录像链路构建。
- 未测发热、电量、音轨完整性、系统中断和 AI 对长期录像的实际影响。
- 不能保证强杀瞬间未封装 MOV 可播放；损坏原件保守保留。

Next:
- 连接真实设备，从 Phase 1 起逐项验收，再依次做 2／4／8 小时测试并填写 TESTING.md 表格。

## 本轮命令行证据

- `./scripts/build.sh Debug`：PASS，未签名 iPhone arm64 App。
- `./scripts/build.sh Release`：PASS，未签名 iPhone arm64 App，Debug 开发控件排除。
- `./scripts/test-core.sh`：34 项断言 PASS；包括临时生成的真实 MOV 恢复和损坏文件保留。
- `./scripts/test-web.sh`：5 项真实 HTTP 传输／配对检查 PASS，业务数据为测试夹具。
- `node --check EverFrame/Web/app.js`：PASS。
- Info.plist、PrivacyInfo.xcprivacy：plutil 检查 PASS。
- 编译器 Swift 源码错误：无。Xcode AppIntents metadata 提取工具提示没有 AppIntents 依赖；项目未使用该能力，无需加入。


## 后续：2026-10-15 真机签名构建

- 已检测到用户连接的 iPhone 8 Plus / iOS 16.7.16。
- 保留用户在 Xcode 设置的 Team 与 Bundle Identifier，没有重新生成或覆盖工程。
- 直接 target 的 Debug arm64 **签名构建 PASS**，未要求先安装模拟器 runtime。
- codesign 严格校验 PASS；embedded.mobileprovision 包含连接设备，App 标识匹配且未过期。
- 已生成项目外的开发 IPA，大小约 0.7 MB，供 Devices 窗口手动安装；签名包含个人开发凭据，不进入仓库。
- 安装结果、启动、摄像头、音轨和长期录像仍 NOT TESTED — NEEDS PHYSICAL DEVICE TEST。
- 本机 Xcode 缓存的运行时索引将 iOS 26.5 / 23F77 标为 MobileAsset；其下载资产为 AAR，不能将其直接当作 DMG 使用 importPlatform。

## 后续：2026-10-15 摄像头切换与记录页优化（0.1.0／构建 2）

已完成：
- 新增实际前后摄像头输入切换；串行事务只替换视频输入，保留麦克风。失败回滚，回滚也失败则清理无效配置并提示下次重建。
- 前置预览单独镜像，文件不镜像；前后输入重设竖屏、可用预设、编码与支持时的24fps。每次会话启动重新激活音频。
- 录制、分段和封装期间禁用镜头切换；App busy／recording 与引擎 recordingPending 双重限制，切换不会停止、丢弃当前文件或自动开始新一轮。
- 去掉记录页大标题、口号、整页滚动与固定260点预览，改用剩余空间取景；底部固定开始／停止、摄像头切换与保留菜单，10／30／60分钟两步可达。
- 统计、AI、回看入口进入详情页，磁盘／温度／中断独立保存警告状态并常驻摘要；普通保留提示不会覆盖警告。
- 保留四个Tab、安全区域与系统动态字体；未生成／覆盖工程，手工签名配置保留。没有新增第三方包、服务器或后台录像。
- README、录像说明和测试手册已更新；权限文案说明首次切换也会启用取景，只有手动开始才写录像。

验证：
- Debug、Release 未签名 arm64 target 构建通过，最低iOS16.0。
- 现有核心CLI：34项断言通过，含真实MOV恢复与保护；HTTP／配对CLI：5项通过。测试夹具与构建日志均位于系统临时目录。
- Personal Team Debug签名构建通过；安装包后续校验与位置见下方交付记录。编译不代表摄像头行为或音轨已验收。
- 本目录仍未初始化Git，无提交和远端写操作；未改动project.pbxproj中的用户签名设置，未将签名材料加入项目。

真机待验收：**NEEDS PHYSICAL DEVICE TEST**。
- 用户已安装并打开初版App；本轮检测到已连接真机，但没有自动覆盖安装、操作摄像头或清空素材。
- 新版前后切换、前置镜像／文件方向、每路真实音轨、失败回滚、权限拒绝与快速连点尚未实测。
- 连续分段、跨段保留、电话／音频中断、后台恢复、磁盘／温度提示、2／4／8小时稳定性仍待真机验证。
- iPhone8 Plus默认／最大辅助字体下的预览大小、警告可见性、停止按钮可达性及详情导航尚无真机截图或运行证据。
- 无已安装的模拟器runtime；没有为此下载大型组件，也没有用构建成功替代上述结果。

开发包交付记录：
- 新包：`~/Downloads/EverFrame-Development/EverFrame-Camera-20261015-Build2.ipa`，0.1.0（2），739971字节；旧`EverFrame-Development.ipa`保留。
- codesign严格校验通过；与旧包的Bundle ID和签名团队一致；有效profile包含当前已连接设备；IPA压缩完整性及内含构建号检查通过。未把个人标识或证书写入文档。
- 开发profile到期时间：2026-10-22 14:36（上海）；到期需用同一身份与Bundle ID重新签名更新，勿先卸载。
- 更新安装：Xcode → Window → Devices and Simulators → Devices → 选择手机 → Installed Apps下方`+` → 选择新IPA；安装后在手机手动打开。不要点击左侧设备列表下方的`+`，不需要卸载旧App。

## 后续：2026-10-15 录制中切换镜头（0.1.0／构建 3）

本节替代构建2“录制期间禁用切换”的交互约束。用户已在真机确认待机可前后切换，并明确要求录制中也能切换。

实现：
- 录制中点击切换，先完成并检查当前MOV，保存实际metadata及最新locked／pendingLock，再配置另一镜头并自动开始下一段。连续会话计时不归零；可能有短暂音画间隔，不保证同文件无缝录像。
- 独立的RecordingContinuation保留续录及单次待切换意图；防止连点排入多次切换，不在文件仍写入时修改AVFoundation输入。
- 切换期间停止按钮仍可用。停止、后台、中断与低磁盘会取消续录，所有异步配置返回后再次检查意图，不能在用户停止后又自动录像。
- 切换失败会确认原镜头会话可运行后继续原镜头；无法恢复则明确停止并保留原文件。正常成功保存的段不因切换重建或删除，原循环存储政策仍适用。
- 只为新增的状态源文件手工增加四处工程登记；反向移除新增行后与原project.pbxproj逐字相同，未运行生成器，用户签名与全部既有工程设置保留。
- README、录像说明与真机测试步骤已同步更新，未加入双录、视频拼接或后台录制。

设备能力：
- iPhone8 Plus不在Apple MultiCam支持硬件内，不能实现前后同时采集再拼屏。官方首批支持设备为iPhone XS／XS Max／XR等；兼容硬件仍应运行时检测isMultiCamSupported和可用设备组合。
- 依据：[Apple WWDC19 MultiCam官方介绍](https://developer.apple.com/videos/play/wwdc2019/249/)。这不是本轮设备运行时采集结果，未以双会话绕过限制。

验证与限制：
- 新增11项可执行状态断言，覆盖重复请求、仅消费一次、保存中停止、配置中停止、后台与中断取消、重新开始清除残留；连同现有检查共45项核心断言通过。
- **NEEDS PHYSICAL DEVICE TEST**：录制中前后切换、切换处真实音画间隔、前置镜像与文件方向、双向音轨、切换失败回退、快速连点、保存／配置期间停止、跨自然分段与保留、后台／电话／低磁盘取消续录、小屏大字体和2／4／8小时稳定性均未实测。
- CLI状态断言不等于真实摄像头或异步硬件集成测试。未安装新包、未卸载旧App、未清空素材。

### 构建3追加：支持机型的前后双录与不支持提示

用户随后授权实际双录功能，本小节替代上节“未加入双录”范围说明。

- 记录页常驻“双录”按钮，详情页也有入口；不支持设备显示本机不支持及XS／XS Max／XR或更新兼容机型的说明。能力判断同时检查MultiCam与前后组合，而非硬编码型号或只判断系统版本；不支持点击不会启用权限、抢占摄像头或中断现有录像。
- 支持设备可停止保存后切换双录模式，再点击开始。独立MultiCam管线配对两路视频，经CoreImage合成上下画面，AVAssetWriter写入单个720×1280 H.264／AAC有声MOV。目标24fps、上后下前、等比填充，预览与文件均不镜像。
- 单镜头的录制中切换继续保留；单／双模式切换需停止保存并串行关闭旧会话，重启默认单镜头。自动分段、保留与存储沿用原流程。
- 双录加入能力、格式、负荷、像素池上限、背压、5秒无音视频写入看门狗、首帧前停止与失败封装处理。最大辅助字体将预览工具按钮与计时分行，停止区域仍独立固定。
- CLI真实CoreImage像素检查最初发现非整数缩放的拼接边缘有半透明像素，已通过缩放前延展边缘修复；重新生成并查看`/tmp/everframe-dual-layout-check/composite.png`，上红下蓝、720×1280；边界像素恢复不透明。该图为合成夹具，不是真机摄像头截图。
- 核心CLI共49项断言通过（11项续录意图、4项真实合成、原有34项）；HTTP／配对5项通过。原工程去除新增3个文件引用后逐字等同备份，用户签名设置未改。
- **NEEDS PHYSICAL DEVICE TEST**：当前iPhone8 Plus不支持双录，未执行新版按钮真机操作；没有兼容MultiCam真机，不能确认实际双录、同步、声音、预览、分段、负荷、能耗、发热或长时稳定性。构建与合成测试不能代替上述验收。

构建3最终交付：
- 最终源码的Debug／Release未签名arm64 target构建、Personal Team Debug签名构建均通过。49项核心断言与5项HTTP／配对检查通过；构建日志在`/tmp/everframe-dual-*.log`。
- 新IPA：`~/Downloads/EverFrame-Development/EverFrame-DualCamera-20261015-Build3.ipa`，0.1.0（3），837062字节；包含本轮单镜头录制中切换与双录功能。构建2和初版IPA均保留供回退。
- codesign严格校验、与旧包的Bundle ID／签名团队比对、profile有效性及已连接设备覆盖、IPA压缩完整性和内含构建号检查全部通过。最终IPA二进制与最新签名App一致，晚于全部Swift源文件。
- profile到期时间仍为2026-10-22 14:36（上海）。安装方式不变：Xcode → Devices and Simulators → 选择手机 → Installed Apps下方`+` → 新IPA。保留相同身份覆盖安装，勿卸载；本轮未代替用户安装或清空任何素材。
