import Foundation
import AVFoundation
import CoreVideo
import CoreImage

@main struct CoreTests {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw AppError.message("测试失败：\(name)") }; count += 1; print("通过：\(name)")
        }
        func rejects(_ name: String, _ block: () throws -> Void) throws {
            var rejected = false; do { try block() } catch { rejected = true }; try check(rejected, name)
        }
        var idle = RecordingIdleDeadline()
        idle.reset(recording: true, active: true, now: 100)
        try check(!idle.expired(at: 159.999) && idle.expired(at: 160), "录制无操作满60秒才调暗")
        idle.reset(recording: true, active: true, now: 150)
        try check(!idle.expired(at: 160) && idle.expired(at: 210), "触摸或恢复亮度后重新计时")
        idle.reset(recording: false, active: true, now: 200)
        try check(!idle.expired(at: 1000), "停止后取消自动调暗")
        idle.reset(recording: true, active: false, now: 200)
        try check(!idle.expired(at: 1000), "离开前台后取消自动调暗")
        var recordingIntent = RecordingContinuation()
        try check(!recordingIntent.requestCameraSwitch(), "待机不能排入录制续接切换")
        recordingIntent.start()
        try check(recordingIntent.shouldContinue(inForeground: true), "普通分段维持续录意图")
        try check(recordingIntent.requestCameraSwitch(), "录制中可排入一次镜头切换")
        try check(!recordingIntent.requestCameraSwitch(), "重复切换不会排入第二个请求")
        try check(recordingIntent.consumeCameraSwitch(), "当前段完成后仅消费一次切换")
        try check(!recordingIntent.consumeCameraSwitch(), "自然分段不会重复切换镜头")
        recordingIntent.stop() // 模拟等待摄像头配置时点击停止。
        try check(!recordingIntent.shouldContinue(inForeground: true), "切换配置期间停止后不能续录")
        recordingIntent.start()
        _ = recordingIntent.requestCameraSwitch()
        recordingIntent.stop() // 模拟当前段尚未封装时点击停止。
        try check(!recordingIntent.consumeCameraSwitch() && !recordingIntent.cameraSwitchPending, "封装期间停止会取消待切换请求")
        recordingIntent.start()
        try check(!recordingIntent.shouldContinue(inForeground: false), "切后台时不得续录")
        _ = recordingIntent.requestCameraSwitch()
        recordingIntent.stop() // 系统中断与低磁盘同样调用停止。
        try check(!recordingIntent.wantsRecording && !recordingIntent.consumeCameraSwitch(), "中断或低磁盘停止清除续录和切换意图")
        recordingIntent.start()
        try check(!recordingIntent.cameraSwitchPending && recordingIntent.shouldContinue(inForeground: true), "手动重新开始没有上轮残留切换")
        let rearImage = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 720, height: 1280))
        let selfieImage = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 100, y: 80, width: 1280, height: 720))
        let composite = DualCameraCompositor.image(back: rearImage, front: selfieImage)
        try check(composite.extent == CGRect(x: 0, y: 0, width: 720, height: 1280), "双录合成固定720×1280竖屏")
        let imageContext = CIContext(options: [.useSoftwareRenderer: true])
        func rgba(_ x: CGFloat, _ y: CGFloat) -> [UInt8] {
            var pixel = [UInt8](repeating: 0, count: 4)
            imageContext.render(composite, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return pixel
        }
        let topPixel = rgba(360, 1000), bottomPixel = rgba(360, 100)
        try check(topPixel[0] > 240 && topPixel[2] < 10 && topPixel[3] == 255, "合成上半部来自后置且不透明")
        try check(bottomPixel[2] > 240 && bottomPixel[0] < 10 && bottomPixel[3] == 255, "合成下半部来自前置，支持不同尺寸和原点")
        try check(rgba(0, 639)[2] > 240 && rgba(719, 640)[0] > 240, "双画面边界无黑缝，等比填充覆盖输出")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("everframe-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try ClipRepository(root: root)
        let now = Date()
        func make(_ minutesAgo: Double, duration: Double = 600, locked: Bool = false, pending: Bool = false, writing: Bool = false, size: Int64 = 100_000_000) throws -> Clip {
            let start = now.addingTimeInterval(-minutesAgo * 60)
            let value = Clip(fileName: "2026-10-15/\(UUID()).mov", startAt: start, endAt: writing ? nil : start.addingTimeInterval(duration), duration: writing ? 0 : duration, fileSize: size, locked: locked, pendingLock: pending)
            try repo.save(value); return value
        }
        let older = try make(80)
        let boundary = try make(35)
        let middle = try make(20)
        let current = try make(5, writing: true)
        try repo.keep(minutes: 30, now: now)
        try check(repo.clips.first(where: { $0.id == boundary.id })?.locked == true, "保留30分钟覆盖与窗口相交的上一片段")
        try check(repo.clips.first(where: { $0.id == middle.id })?.locked == true, "保留窗口内片段")
        try check(repo.clips.first(where: { $0.id == current.id })?.pendingLock == true, "当前片段 pendingLock 持久化")
        let reloaded = try ClipRepository(root: root)
        try check(reloaded.clips.first(where: { $0.id == current.id })?.pendingLock == true, "重启读取 pendingLock")
        try check(reloaded.clips.first(where: { $0.id == older.id })?.locked == false, "窗口外片段不锁定")
        try rejects("拒绝非法保留时长") { try repo.keep(minutes: 11) }
        try rejects("禁止删除当前片段") { try repo.delete(current.id, confirmLocked: true) }
        try rejects("已保留文件需要二次确认") { try repo.delete(middle.id) }
        try repo.keep(minutes: 10, now: now)
        try repo.keep(minutes: 60, now: now)
        try check(repo.clips.filter { $0.locked || $0.pendingLock }.count == 3, "10/30/60分钟保护可重复执行")
        var policy = AppSettings(); policy.maxStorageGB = 0.3; policy.minimumFreeGB = 1
        let candidates = StoragePolicy.candidates(clips: repo.clips, now: now, settings: policy, free: 20_000_000_000, pinned: [])
        try check(candidates == [older.id], "空间清理只选最老未保护文件")
        let pinned = StoragePolicy.candidates(clips: repo.clips, now: now, settings: policy, free: 0, pinned: [older.id])
        try check(pinned.isEmpty, "低空间也不能删除保护/当前/分析占用的片段")
        var veryOld = older; veryOld.startAt = now.addingTimeInterval(-9*86400)
        policy.maxStorageGB = 40
        try check(StoragePolicy.candidates(clips: [veryOld], now: now, settings: policy, free: 20_000_000_000, pinned: []) == [older.id], "年龄触发清理")
        let analyses = try TimelineRepository(root: root)
        let transcript = Transcript(clipID: middle.id, segments: [.init(start: 4, end: 8, text: "ESP32 测试成功")])
        try analyses.save(transcript)
        let json = """
        ```json
        {"summary":"工作讨论","topics":["产品"],"importance_score":82,"suggested_review":true,"review_reason":"完整观点","timeline":[{"start":4,"end":8,"title":"技术突破","summary":"测试成功","importance_score":88}],"ideas":[{"timestamp":5,"text":"记录工作"}]}
        ```
        """
        let analysis = try AIJSON.decode(ClipAnalysis.self, text: json).validated(duration: 600)
        try analyses.save(analysis, id: middle.id)
        try check(analyses.matches(middle, query: "esp32"), "搜索转写大小写不敏感")
        try check(analyses.matches(middle, query: "产品"), "搜索主题")
        let loadedAnalysis = try TimelineRepository(root: root)
        try check(loadedAnalysis.analyses[middle.id] == analysis, "分析 JSON 原子持久化后恢复")
        try check(loadedAnalysis.transcripts[middle.id]?.segments == transcript.segments, "带时间戳转写恢复")
        var invalid = analysis; invalid.timeline[0].end = 900
        try rejects("拒绝模型越界时间戳") { _ = try invalid.validated(duration: 600) }
        try rejects("拒绝无效模型 JSON") { _ = try AIJSON.decode(ClipAnalysis.self, text: "```json\n{}") }
        let sr = try SettingsRepository(root: root)
        try sr.save(policy)
        try check(try SettingsRepository(root: root).value.segmentMinutes == 10, "默认分段仍为10分钟")
        var badSettings = policy; badSettings.segmentMinutes = 1
        try rejects("正式设置拒绝测试分段") { try sr.save(badSettings) }
        let pair = PairingStore()
        let token = try pair.pair(pair.code)
        try check(token.count == 64 && pair.authorized("Bearer " + token), "256位随机会话验证")
        try check(!pair.authorized(nil), "匿名请求拒绝")
        pair.reset()
        try check(!pair.authorized("Bearer " + token), "重配对撤销旧会话")
        let wrong = pair.code == "000000" ? "111111" : "000000"
        for _ in 0..<5 { _ = try? pair.pair(wrong) }
        try rejects("配对暴力猜测限流") { _ = try pair.pair(pair.code) }
        let request = Data("POST /api/keep HTTP/1.1\r\nHost: 192.168.1.2:8080\r\nContent-Type: application/json\r\nContent-Length: 14\r\n\r\n{\"minutes\":30}".utf8)
        try check(try HTTPParser.parse(Data(request.dropLast())) == nil, "不完整 HTTP body 等待后续数据")
        let parsed = try HTTPParser.parse(request)
        try check(parsed?.path == "/api/keep" && parsed?.body == Data("{\"minutes\":30}".utf8), "分包 HTTP 解析正确")
        for (name, input) in [
            ("重复长度头", "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n"),
            ("分块请求", "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"),
            ("超大请求", "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 999999\r\n\r\n"),
            ("HTTP pipeline", "GET / HTTP/1.1\r\nHost: x\r\n\r\nextra")
        ] { try rejects("拒绝" + name) { _ = try HTTPParser.parse(Data(input.utf8)) } }
        let recoveryRoot = root.appendingPathComponent("recovery")
        let recovery = try ClipRepository(root: recoveryRoot)
        let validURL = recovery.clipsURL.appendingPathComponent("2026-10-15/orphan.mov")
        try FileManager.default.createDirectory(at: validURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await makeVideo(validURL)
        let missing = Clip(fileName: "2026-10-15/missing.mov", startAt: now)
        try recovery.save(missing)
        let corruptURL = recovery.clipsURL.appendingPathComponent("2026-10-15/corrupt.mov")
        try Data("broken".utf8).write(to: corruptURL)
        await CrashRecovery.run(recovery)
        try check(!recovery.clips.contains { $0.id == missing.id }, "恢复移除无视频索引")
        let recovered = recovery.clips.first { $0.fileName.hasSuffix("orphan.mov") }
        try check(recovered != nil && recovered!.duration > 0 && recovered!.locked, "真实MOV孤立文件恢复时长并保守保护")
        let broken = recovery.clips.first { $0.fileName.hasSuffix("corrupt.mov") }
        try check(broken?.locked == true && broken?.failure != nil, "损坏MOV不丢弃且标记保护和错误")
        try check(FileManager.default.fileExists(atPath: corruptURL.path), "恢复过程保留损坏原文件")
        print("全部 \(count) 项断言通过；临时目录退出后清理。")
    }
    static func makeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String:32, kCVPixelBufferHeightKey as String:32])
        writer.add(input); guard writer.startWriting() else { throw AppError.message("测试视频编码无法启动") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess, let buffer else { throw AppError.message("测试像素创建失败") }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else { throw AppError.message("测试视频写入失败") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw AppError.message("测试视频封装失败") }
    }
}
