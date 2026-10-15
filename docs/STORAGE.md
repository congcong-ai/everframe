# 存储、保护与恢复

## 数据目录

```text
Documents/
  diagnostics.log
  EverFrame/
    settings.json
    recording-session.json       # 仅录像会话期间存在
    Clips/yyyy-MM-dd/
      HH-mm-ss-SSS.mov
      HH-mm-ss-SSS.json
    Analysis/
      UUID.transcript
      UUID.json
    DailySummaries/
      yyyy-MM-dd.json
```

JSON 日期以 Swift Codable Date 形式保存；局域网 API 则统一输出 ISO 8601。文件路径存相对路径，不记录本机绝对路径。每个 metadata 原子替换，不维护单个易损的全局影片索引。目录排除系统自动备份，重要内容需要用户手动导出。

## 配额

默认最大 40 GB、普通素材最长 7 天、尽量保留系统 15 GB。启动、每段封装及运行中定期检查；清理按最旧优先，任一条件触发即可入选。当前写入、locked、pendingLock 和正在分析的素材始终跳过。

300 MB 是 Debug 清理验收配置，不是默认值。当前段可能暂时超过配额；配额不是在文件写入途中强制截断。若保护素材过多导致目标无法达成，显示提示。实际空间低于 1 GB 时停止录像，MovieFileOutput 还设置 500 MB 底线。空间读取失败也按不安全处理。安全停止与配额清理不同，不能为了满足配额删除保留素材。

## 保留最近

窗口 `[现在-N分钟, 现在]` 与片段 `[开始, 结束]` 相交即锁定整个片段。当前片段没有结束时间，立即原子写 pendingLock；最终封装时转 locked。边界片段可能让总保护时长超过 N 分钟。已经删除或从未录到的内容不能被恢复。支持取消保护，但不允许删除正在写入或 pendingLock 的文件。

## 删除与派生数据

人工删除必须确认；保留素材有明确二次警告。先删视频，失败则保留 metadata，避免丢掉保护信息。随后删 metadata 和对应转写／分析。每日总结是历史快照，独立保存，可能保留已删除片段的文字；界面不再为不存在的片段显示播放按钮。

## 非正常退出

- 视频存在、metadata 缺失／损坏：根据 AVAsset 与文件时间重建，默认保护，防止原先锁定状态丢失造成误删。
- metadata 存在、视频不存在：移除孤立索引。
- 未封装但可读：补时长、大小、结束时间，保留 pendingLock。
- 无法读取的 MOV：保留原文件并锁定，标为失败，禁止进入 AI 队列。
- running 作业：恢复 pending；完成的转写可复用。
- 存在上次录制会话标记：记录“上次会话异常结束”，但不自动开启摄像头。

没有任何实现能保证被强杀瞬间正在封装的 MOV 全部可恢复。请先导出损坏文件，不要靠卸载排错。
