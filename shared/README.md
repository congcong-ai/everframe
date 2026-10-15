# 双端共同规则与交换协议

iOS保留SwiftUI/AVFoundation，Android使用Kotlin/Compose/CameraX。这里只放真正共用的规则与测试样例，不引入跨平台运行时，也不移动既有iOS文件。

## 录像与保护

- 默认10分钟分段，可选5/10/15/30；分段允许短暂间隙。
- 保留最近10/30/60分钟：闭区间相交条件为 `片段开始 <= 当前时间 && 片段结束 >= 当前时间 - 窗口`。写入中片段的结束按当前时间计算；保护整段，不裁切。
- 写入中先持久化 `pendingLock`，封装时重新读取最新值并转成 `locked`。
- 配额40GB、普通素材7天、目标剩余15GB，按最旧未保护段清理；不删除当前、pendingLock、locked或正在分析/播放/导出的段。低于1GB安全停止。
- 不后台录像。后台、中断、停止或低空间撤销自动续录；迟到的保存回调不能重启录像。
- 恢复不丢弃损坏原文件；元数据丢失时保守保护。恢复不等于修复未封装音视频。

## 日期、素材与文字

HTTP交换日期统一ISO 8601 UTC字符串；UUID引用原视频，时间轴start/end是原录像内的相对秒数，不生成剪辑文件。

`Clip`共同字段：id、fileName、createdAt、startAt、endAt、duration、fileSize、codec、width、height、fps、locked、pendingLock、transcriptionStatus、aiStatus、summary、importanceScore、failure。

`transcriptionStatus` / `aiStatus`取pending/running/completed/failed。`endAt == null`表示正在写入。HTTP字段协议一致，不代表可以直接互换全部私有存储：iOS落盘日期沿用现有Swift Codable编码、MOV按天目录存储；Android为ISO日期JSON、UUID命名MP4。此阶段不提供双端数据库迁移或同步。

转写与AI字段以 `EverFrame/Models/AIModels.swift` 为既有参照，Android `Models.kt` 对齐。样例在 `fixtures/`：

- `transcript.zh-CN.json`：clipID、locale、segments[{start,end,text}]。
- `analysis.zh-CN.json`：summary、topics、importance_score、suggested_review、review_reason、timeline、ideas。

样例仅用于测试，不能作为实际识别结果。Android导入前必须替换clipID，校验时间在原录像实际时长内。AI分数0..100，时间有限且非负、end>start，拒绝未知每日总结素材引用。日志和HTTP不输出Key或完整转写。

## 局域网 API

两端复用 `EverFrame/Web/` 中的HTML/JS/CSS，Android打包引用原目录。所有控制API除配对外要求 `Authorization: Bearer 令牌`，修改用 `Content-Type: application/json`，Origin存在时必须同源。

| 方法 | 路径 | 内容 |
| --- | --- | --- |
| POST | /api/pair | {code:六位码} → {token} |
| GET | /api/status | name、recording、busy、elapsed、todaySeconds、usedBytes、freeBytes、ai、message |
| POST | /api/start | 请求开始；权限必须已在手机授予 |
| POST | /api/stop | 停止并取消续录 |
| POST | /api/keep | {minutes:10/30/60} |
| GET | /api/clips | 最新至多500段 |
| POST | /api/clips/{UUID}/lock 或 unlock | 保留/取消 |
| GET | /api/timeline | 当天事件与原素材UUID、绝对日期 |
| GET / POST | /api/daily-summary | 读取/请求生成今日总结 |
| GET / POST | /api/settings | 读取设置/仅修改录像存储参数 |

POST设置只允许segmentMinutes、maxStorageGB、retentionDays、minimumFreeGB。AI授权、密钥、网络启停必须在手机操作。长操作异步接收不代表已完成，需要再读status/素材。错误返回JSON {error:中文说明}。不提供网页下载原始录像、删除素材或读取密钥接口。

配对码每次监听会话生成，五次错误冷却一分钟，会话最多八个、12小时过期；关闭监听、切后台或温度暂停会作废令牌。只适合可信Wi-Fi，HTTP传输不加密。没有云端远程控制。
