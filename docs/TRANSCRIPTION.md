# 语音转写

协议 TranscriptionProvider，V1 实现 AppleSpeechTranscriptionProvider，默认 zh-CN。不提供 Whisper 或云 STT 实现，只保留替换边界。

## 授权与隐私

手机设置页单独请求 SFSpeechRecognizer 授权。优先 `supportsOnDeviceRecognition`；不支持时默认拒绝在线发送。只有用户在手机确认“允许 Apple 在线语音识别”后，才允许在线请求。在线音频由 Apple 处理；无网络、语言不可用、系统限流、权限拒绝都变成可重试失败，不影响录像。

## 长音频

[Apple 的 SFSpeechRecognizer 文档](https://developer.apple.com/documentation/speech/sfspeechrecognizer)要求考虑约一分钟的任务限制。录制完成后，AVAssetExportSession 提取每段最多 55 秒的 M4A 到系统临时目录，按顺序交给 SFSpeechURLRecognitionRequest。每块识别恢复相对原录像的秒偏移，保存 start、end、text，不保存临时音频。块内断句边界可能影响识别质量，需要实测 1 分钟与 10 分钟内容。

每块最多等待 90 秒。回调、超时和任务取消经过锁保护，continuation 只完成一次。任一块失败不会保存不完整的整段转写，用户可稍后重试，避免把部分结果误认为完整。

## 性能

最多一个片段进入分析队列。每次音频导出与识别之间检查前台、温度、网络／充电条件和取消状态。serious／critical 暂停并取消识别；恢复后重新排队。临时目录在任务完成时清理，异常退出遗留会在下次启动清理。

A11 的本地中文模型、识别准确率、音频提取速度与电池影响均 NEEDS PHYSICAL DEVICE TEST。无讲话、识别失败和没录到声音是不同情况；不根据无文本猜测视觉工作内容。
