# 录像

实现为 AVFoundation / AVCaptureMovieFileOutput；最低 iOS 16.0。默认后置 1280×720，优先 24fps；设备 activeFormat 支持时设定最短／最长帧间隔。优先 HEVC，否则 H.264。MovieFileOutput 负责 MOV 与默认 AAC 音轨封装；最终 metadata 从文件读取实际视频编码、尺寸和 fps。真机验收必须确认音轨与实际编码，不能从配置推断文件正确。

## 状态与分段

准备 → 请求摄像头／麦克风 → 配置 capture session → 建立 metadata → 写文件。按钮启动阶段防止重复点击；停止时等待 delegate 完成，不允许立即开启另一轮。`maxRecordedDuration` 控制分段，默认 600 秒；Debug 可设置 30／60 秒。每段结束后先封装与保存，再续录，允许短间隔。

结束时检查 AVErrorRecordingSuccessfullyFinishedKey：正常时长上限结束不被误判为坏文件。出现真正错误时停止，不无限重启摄像头。摄像头中断／运行时错误提示用户手动恢复。录制结束后的异步 metadata 检查会重读保护状态，避免用户在封装中点击“保留”被旧状态覆盖。

## 前台和电源

录制开始后禁用自动锁屏；停止、失败、切后台恢复正常。始终展示 REC 和“正在记录”。使用系统亮度设置手动调低屏幕。不使用后台音频、定位、VoIP entitlement。有限 background task 仅用于完成已经开始的文件封装，不能维持摄像头。

当前画面只在手机预览，不为电脑建立 HLS／WebRTC 管线。暂未实现可选 snapshot 接口。

## 文件命名

`Documents/EverFrame/Clips/yyyy-MM-dd/HH-mm-ss-SSS.mov`。毫秒后缀避免同一秒快速重启覆盖文件。相邻 JSON 保存 metadata。此路径与显示名称解耦。

## 真机必测

1. 开始／停止十轮，全部能播放、有声，控制台无 capture 错误。
2. Debug 1 分钟连续录 10 分钟，约 10 段；逐一确认音轨与切换间隙。
3. 恢复默认 10 分钟；检查电话、锁屏、切后台、前台恢复和拒绝权限。
4. 进行 2／4／8 小时测试；当前全部标为 NEEDS PHYSICAL DEVICE TEST。

## 摄像头切换与取景

待机可直接切换。录制中点击切换会设置一次待切换意图，调用引擎停止当前段但保留会话续录意图；didFinish 回调后先完成文件检查、实际metadata与最新保护标记落盘，再切换镜头并创建下一段。连续会话计时不重置，音画可能有短暂间隔，不是同一MOV中的无缝切换。

AppModel 的 busy／cameraSwitching 防止重复切换；RecordingContinuation 独立保存续录与待切换意图。保存或配置摄像头期间，停止按钮仍可操作；stop 会清除待切换与续录意图。每次异步配置返回后必须重新检查前台及续录意图，避免用户已停止、切后台、系统中断或低磁盘后又自动录制。录像引擎 recordingPending 继续禁止在文件实际写入过程中更换输入。只有当前段成功封装才会尝试切换；失败段保留并明确停止。

首次点击切换也会请求摄像头和麦克风权限并启动取景，但不会创建素材或写文件。切换只更换视频输入，麦克风保留；beginConfiguration／commitConfiguration 成对执行。新摄像头重新选择支持的 720p／high 预设，在当前格式支持时设为 24fps，并重设竖屏、编码及文件不镜像。前置预览单独镜像。失败时回滚到原输入；录制会话会确认原摄像头可运行，再继续原镜头并显示警告。原输入也无法恢复时停止会话并保留原文件，下次需手动开始。用户停止后绝不自动续录。每次启动会话都会重新激活音频会话，避免停止后再次录制时仍处于音频停用状态。

记录页取消大标题与整页滚动，取景占用剩余空间；底部操作区独立于取景尺寸，开始／停止、切换及保留入口固定可达。统计和 AI 状态在详情页，磁盘／温度／录像异常的摘要常驻，完整警告在详情中可读。

实现参考：[Apple 摄像会话配置说明](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)。这只支持 API 使用方式，不证明具体设备表现。

## 双摄像头同时采集

记录页与详情页的“双录”按钮先检查AVCaptureMultiCamSession.isMultiCamSupported以及前后广角摄像头组合。iPhone8 Plus等不支持设备只弹提示，不请求权限、不停止正在进行的普通录像。提示说明通常需要iPhone XS／XS Max／XR或更新兼容机型，并非仅凭型号年份判断。切换单镜头／双录模式必须先停止并保存，串行关闭原管线后才选择另一管线；不会在写文件中途替换整个引擎，重启App默认单镜头。

DualRecordingEngine单独使用MultiCamSession，两路输入各选择支持MultiCam的低分辨率格式，目标24fps；显式连接视频／音频端口，检查hardwareCost与systemPressureCost，不符合则报错并保留单镜头操作入口。视频通过AVCaptureDataOutputSynchronizer配对后送入CoreImage等比裁切，上方后置、下方前置，合成720×1280。预览和文件均不镜像。像素池最多分配6个画面，预览主线程最多排一个回调，写入按readyForMoreMediaData处理背压。

AVAssetWriter输出H.264视频与AAC单声道音轨，首个视频时间戳作为会话起点；音频采用同一capture session时间轴。默认每10分钟完成MOV，复用AppModel的实际metadata、保护、清理与续录流程。5秒MOV碎片用于降低未封装损失，不保证强杀可恢复。音频或画面超过5秒未成功写入会结束当前文件并报错；没有完整音视频不会被默认为成功录像。停止首帧前也会完成回调而非无限等待。

双录会增加功耗、发热和画面裁切。系统可能中断；没有后台双录。当前无兼容真机，采集同步、音轨、编码、持续分段、发热及2／4／8小时稳定性全部为NEEDS PHYSICAL DEVICE TEST。CLI只验证真实CoreImage合成结果及状态语义，不能替代硬件验收。

参考：[Apple MultiCam官方介绍](https://developer.apple.com/videos/play/wwdc2019/249/)及[Apple双摄像头合成示例](https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras)。
