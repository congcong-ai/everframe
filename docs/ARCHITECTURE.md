# 架构

本地优先的单用户 iOS 16 App，无后端、无外部 Swift 包。SwiftUI 四个功能页共享主 actor 上的数据仓库；摄像头配置、启动和停止在独立串行队列。Network.framework 连接在独立 utility 队列收包；有限大小的请求才进入主 actor 执行业务。

## 分层与职责

| 层 | 对象 | 职责 |
| --- | --- | --- |
| 启动协调 | Bootstrap / AppModel | 恢复、录制状态机、生命周期、调度与温度 |
| 录像 | RecordingEngine / MovieRecordingEngine | AVFoundation 录制与结束回调 |
| 存储 | ClipRepository / StorageManager | metadata 原子持久化、保护、配额、删除 |
| 数据 | TimelineRepository / DailySummaryRepository / SettingsRepository | 独立本机 JSON，可替换数据库实现 |
| 语音 | TranscriptionProvider / AppleSpeechTranscriptionProvider | 提取音频、55 秒块转写和绝对偏移 |
| AI | AIProvider / DeepSeekProvider / AnalysisQueue | 严格 JSON、单任务串行、重试与每日总结 |
| 安全 | KeychainStore / PairingStore | API Key、本次启动的配对会话 |
| 网络 | LocalWebServer / HTTPParser / WebAPI | 有界 HTTP/1.1、认证、资源与控制接口 |

## 关键数据流

点击开始 → 权限 → 检查空间 → 持久化当前片段 metadata → MovieFileOutput 写入 → 封装 → 读取实际时长、大小和编码 → 重新读取最新保护状态 → metadata 原子落盘 → 清理 → 下一段 → 非关键分析队列。

转写 / AI 按最旧待处理片段串行，一次一个任务。AI 网络等待不会占据摄像头队列。录像分段结束不等待 Speech 或 DeepSeek。分析中的文件加入存储保护集合，避免被循环删除。

## 可替换边界

RecordingEngine 可换 AVAssetWriter；TranscriptionProvider 可换 Whisper／CloudSTT；AIProvider 可换其它模型；FrameExtractor 仅预留协议。仓库目前为具体 JSON 实现，功能与数据落盘职责分离，未来可在仓库内部迁移 SQLite／Core Data，不引入 SwiftData。

AppModel 负责跨组件协调，不负责 HTTP 解析、语音识别细节、AI prompt 解析或每个页面排版。数据模型使用 UUID 引用原录像；时间轴只持有相对秒数，不创建剪辑文件。

## 异常隔离

- 无 Key、断网、识别限流、JSON 错误：仅当前 AI 作业失败，录像继续。
- 进入后台：停止录像，使用有限系统后台时间尽力封装，绝不后台持续调用摄像头。
- serious：取消非关键分析；critical：再关闭电脑控制。系统实际是否停止摄像头不受 App 保证。
- 原子 metadata 写入只防止半截 JSON；MOV 被强杀仍可能无法播放。恢复时保留损坏原文件，不承诺恢复所有帧。


## Android 原生实现

新增独立 `android/` 工程，不重写或移动 iOS。Android 使用 Compose 四页、CameraX、私有MP4/原子JSON、Keystore、有限局域网HTTP与可选DeepSeek。复用现有 `EverFrame/Web/` 资源；共同功能规则和HTTP/AI数据字段见 [shared](../shared/README.md)。Android文件转写是默认关闭且需真机验证的系统端侧实验功能，不等同Apple Speech。详细状态机、生命周期与能力降级见 [Android说明](../android/README.md)。
