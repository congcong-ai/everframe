import SwiftUI
import AVFoundation

@MainActor final class AppModel: ObservableObject {
    let clips: ClipRepository
    let settings: SettingsRepository
    let timeline: TimelineRepository
    let daily: DailySummaryRepository
    let storage: StorageManager
    let analysis: AnalysisQueue
    let pairing = PairingStore()
    private let singleEngine = MovieRecordingEngine()
    private(set) lazy var dualEngine = DualRecordingEngine()
    var engine: RecordingEngine { dualRecording ? dualEngine : singleEngine }
    @Published private(set) var dualRecording = false
    @Published var cameraNotice: String?
    static let dualCameraRequirement = "这台 iPhone 不支持前后摄像头同时录制。通常需要 iPhone XS／XS Max／XR 或更新的兼容机型；并非所有后续型号都支持，最终以设备的 MultiCam 能力和前后摄像头组合检测为准。当前可以使用单镜头录像及录制中切换。"
    private let server = LocalWebServer()
    private lazy var webAPI = WebAPI(app: self, pairing: pairing)
    @Published var recording = false
    @Published var busy = false
    @Published var ready = false
    @Published var foreground = true
    @Published var message = "固定手机、接通电源，再开始记录。"
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var cameraSwitching = false
    @Published var recordingWarning: String?
    @Published var storageWarning: String?
    @Published var thermalWarning: String?
    @Published var webState = "关闭"
    @Published var startedAt: Date?
    @Published var clock = Date()
    private var activeID: UUID?
    private var continuation = RecordingContinuation()
    private var startCancelled = false
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var lastThermal = ProcessInfo.processInfo.thermalState
    private var tickCount = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var sessionMarker: URL { clips.root.appendingPathComponent("recording-session.json") }
    var canStopRecording: Bool { recording && continuation.wantsRecording }
    var elapsed: Double { recording ? max(0, clock.timeIntervalSince(startedAt ?? clock)) : 0 }
    var todaySeconds: Double {
        let dayStart = Calendar.current.startOfDay(for: clock)
        return clips.clips.reduce(0) { total, clip in
            let end = clip.endAt ?? clock
            return total + max(0, min(end, clock).timeIntervalSince(max(clip.startAt, dayStart)))
        }
    }
    var webAddress: String { LocalWebServer.address ?? "请连接 Wi-Fi" }
    init() throws {
        clips = try ClipRepository()
        settings = try SettingsRepository(root: clips.root)
        timeline = try TimelineRepository(root: clips.root)
        daily = try DailySummaryRepository(root: clips.root)
        storage = StorageManager(clips: clips, timeline: timeline)
        analysis = AnalysisQueue(clips: clips, timeline: timeline, daily: daily, settings: settings, storage: storage)
        bind(engine: singleEngine)
        server.handler = { [weak self] request in
            guard let self else { return .json(["error":"服务关闭"], status: 503) }
            return await self.webAPI.handle(request)
        }
        server.stateChanged = { [weak self] state in Task { @MainActor in self?.webState = state } }
    }
    private func bind(engine: RecordingEngine) {
        engine.onFinished = { [weak self] url, error in Task { @MainActor in await self?.finished(url, error: error) } }
        engine.onInterruption = { [weak self] in Task { @MainActor in self?.stop(); self?.message = "摄像头被中断，请保持前台并手动重新开始。"; self?.recordingWarning = "摄像头或音频被中断，请手动重新开始。"; AppLogger.shared.log("录像中断") } }
    }
    func toggleDualRecording() async {
        guard ready, !busy, !cameraSwitching else { return }
        guard dualRecording || DualRecordingEngine.isSupported else { cameraNotice = Self.dualCameraRequirement; return }
        guard !recording else { cameraNotice = "请先停止并保存当前录像，再切换单镜头／双录模式。单镜头录制中仍可直接切换前后镜头。"; return }
        busy = true
        defer { busy = false }
        engine.onFinished = nil; engine.onInterruption = nil
        engine.shutdown() // 同一管线串行完成关闭，再启用另一管线，不能同时抢占摄像头。
        await engine.waitUntilStopped()
        dualRecording.toggle()
        bind(engine: engine)
        message = dualRecording ? "双录已选择：上方后置、下方前置。点击开始后启用两路摄像头，画面不镜像。" : "已切回单镜头录像。点击开始或切换按钮启用取景。"
    }
    func prepare() async {
        guard !ready else { return }
        if FileManager.default.fileExists(atPath: sessionMarker.path) {
            message = "上次记录会话异常结束，正在恢复文件。"
            AppLogger.shared.log("上次会话异常结束")
        }
        await CrashRecovery.run(clips)
        // 清理意外退出遗留的临时音频，原视频不受影响。
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Speech")
        try? FileManager.default.removeItem(at: temp)
        try? FileManager.default.removeItem(at: sessionMarker)
        ready = true
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.thermalChanged() }
        }
        thermalChanged()
        applyWebSetting()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func tick() {
        clock = Date(); tickCount += 1
        guard ready else { return }
        if tickCount % 5 == 0 {
            if recording {
                do { try storage.requireSafeSpace(settings: settings.value) }
                catch { message = error.localizedDescription; storageWarning = message; AppLogger.shared.log("磁盘危险阈值，安全停止录像"); stop() }
            }
            analysis.tick()
        }
        if tickCount % 30 == 0 {
            do {
                try storage.clean(settings: settings.value)
                if storage.usedBytes > settings.value.maxBytes || storage.freeBytes < Int64(settings.value.minimumFreeGB * 1_000_000_000) {
                    storageWarning = "存储目标尚未满足；请及时导出或清理素材。"
                } else {
                    storageWarning = nil
                }
            }
            catch { storageWarning = "自动清理失败，请检查磁盘空间"; AppLogger.shared.log("存储清理失败") }
        }
    }
    func start() async {
        guard ready, foreground, !recording, !busy else { return }
        busy = true; startCancelled = false; defer { busy = false }
        do {
            try storage.clean(settings: settings.value)
            try storage.requireSafeSpace(settings: settings.value)
            try await engine.configure(position: cameraPosition)
            guard foreground, !startCancelled else { engine.shutdown(); return }
            continuation.start(); startedAt = Date(); clock = Date()
            try nextClip()
            UIApplication.shared.isIdleTimerDisabled = true
            recordingWarning = nil
            message = "正在记录"; AppLogger.shared.log("录像开始")
        } catch { continuation.stop(); message = error.localizedDescription; recordingWarning = message; engine.shutdown() }
    }
    func switchCamera() async {
        guard ready, foreground, !dualRecording, !busy, !cameraSwitching else { return }
        if recording {
            guard continuation.requestCameraSwitch() else { return }
            busy = true; cameraSwitching = true
            message = "正在保存当前片段，随后切换镜头并自动续录…"
            // 自然分段已回调时 activeID 为 nil，等待该次 finished 即可，不能重复封装。
            if activeID != nil { engine.stop() }
            return
        }
        busy = true; cameraSwitching = true
        defer { busy = false; cameraSwitching = false }
        let target: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        do {
            try await engine.configure(position: target)
            cameraPosition = target
            message = target == .front ? "已切换前置摄像头；预览镜像，录像不镜像。" : "已切换后置摄像头。"
            if !foreground { engine.shutdown() }
        } catch {
            message = error.localizedDescription
            recordingWarning = message
            if !foreground { engine.shutdown() }
        }
    }
    private func nextClip() throws {
        try storage.requireSafeSpace(settings: settings.value)
        let clip = try clips.create()
        try Data("{\"active\":true}".utf8).write(to: sessionMarker, options: .atomic)
        activeID = clip.id; recording = true
        engine.record(to: clips.url(for: clip), duration: settings.value.segmentSeconds)
    }
    func stop() {
        startCancelled = true
        continuation.stop()
        if activeID != nil { busy = true; engine.stop() }
        else if !recording { engine.shutdown() }
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func finished(_ url: URL, error: Error?) async {
        guard let id = activeID, var clip = clips.clips.first(where: { $0.id == id }) else { return }
        activeID = nil
        busy = true
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite, duration.seconds > 0 else { throw AppError.message("录像文件未能正常封装") }
            clip.duration = duration.seconds; clip.endAt = clip.startAt.addingTimeInterval(duration.seconds)
            clip.fileSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                clip.width = Int(size.width); clip.height = Int(size.height)
                clip.fps = Double(try await track.load(.nominalFrameRate))
                if let description = try await track.load(.formatDescriptions).first {
                    let subtype = CMFormatDescriptionGetMediaSubType(description)
                    clip.codec = subtype == kCMVideoCodecType_HEVC ? "HEVC" : subtype == kCMVideoCodecType_H264 ? "H.264" : "其他"
                }
            }
            // 封装过程中用户可能点击保留，必须重新读取最新持久化保护标记。
            if let current = clips.clips.first(where: { $0.id == id }) { clip.locked = current.locked || current.pendingLock }
            clip.pendingLock = false
            try clips.save(clip)
            AppLogger.shared.log("录像封装完成")
            let ns = error as NSError?
            let successful = ns == nil || (ns?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
            if continuation.shouldContinue(inForeground: foreground) && successful {
                if continuation.consumeCameraSwitch() { try await switchRecordingCamera() }
                // 配置摄像头期间用户可能停止、切后台或遇到中断，必须在 await 后再次检查。
                guard continuation.shouldContinue(inForeground: foreground) else {
                    settleStopped("已停止记录，当前片段已保存")
                    return
                }
                try storage.clean(settings: settings.value)
                try nextClip() // 先续录，再唤醒非关键任务。
                busy = false; cameraSwitching = false
            } else {
                if !successful { recordingWarning = "录像异常结束，当前文件已保留：\(error?.localizedDescription ?? "请检查空间和设备状态")" }
                settleStopped(successful ? "已停止记录" : "录像异常结束，请检查空间和设备状态")
            }
            analysis.tick()
        } catch {
            recordingWarning = "保存、切换或续录失败，原文件已保留：\(error.localizedDescription)"
            settleStopped("记录已停止，请查看警告与现有素材")
            AppLogger.shared.log("录像封装、切换或续录失败")
        }
    }
    private func switchRecordingCamera() async throws {
        let previous = cameraPosition
        let target: AVCaptureDevice.Position = previous == .back ? .front : .back
        do {
            try await engine.configure(position: target)
            cameraPosition = target
            guard continuation.shouldContinue(inForeground: foreground) else { return }
            message = "已切换\(target == .front ? "前置" : "后置")摄像头，继续记录。切换处可能有短暂间隔。"
            AppLogger.shared.log("录制会话切换摄像头，当前段已保存")
        } catch {
            guard continuation.shouldContinue(inForeground: foreground) else { return }
            // 引擎已尝试回滚，再确认原镜头会话可运行后才允许续录。
            try await engine.configure(position: previous)
            guard continuation.shouldContinue(inForeground: foreground) else { return }
            recordingWarning = "镜头切换失败，已恢复原镜头继续记录；切换处可能有短暂间隔。"
            message = recordingWarning ?? "原镜头继续记录"
            AppLogger.shared.log("镜头切换失败，恢复原镜头")
        }
    }
    private func settleStopped(_ text: String) {
        continuation.stop(); recording = false; busy = false; cameraSwitching = false
        engine.shutdown(); UIApplication.shared.isIdleTimerDisabled = false
        message = text
        // 如果仍有未封装 metadata，保留异常会话标记供下次恢复。
        if !clips.clips.contains(where: \.isWriting) { try? FileManager.default.removeItem(at: sessionMarker) }
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func keep(_ minutes: Int) {
        do { try clips.keep(minutes: minutes); message = "已保留最近\(minutes)分钟内的现有素材" }
        catch { message = error.localizedDescription }
    }
    func remove(_ clip: Clip, confirmed: Bool) throws {
        guard analysis.workingID != clip.id else { throw AppError.message("该素材正在分析，请稍后删除") }
        try clips.delete(clip.id, confirmLocked: confirmed); try timeline.remove(clip.id)
    }
    func updateSettings(_ value: AppSettings) throws {
        let changed = value.webEnabled != settings.value.webEnabled
        try settings.save(value)
        if changed { pairing.reset(); applyWebSetting() }
        analysis.tick()
    }
    private func thermalChanged() {
        let state = ProcessInfo.processInfo.thermalState
        thermalWarning = state == .critical ? "设备温度过高，AI 与电脑控制已暂停；系统可能中断录像。" : state == .serious ? "设备温度偏高，语音与 AI 已暂停。" : nil
        analysis.tick()
        AppLogger.shared.log(state == .serious || state == .critical ? "设备温度偏高，暂停非关键任务" : "设备温度恢复")
        if state == .critical { server.stop(); webState = "温度过高，电脑控制暂停" }
        else if lastThermal == .critical { applyWebSetting() }
        lastThermal = state
    }
    private func applyWebSetting() {
        guard ProcessInfo.processInfo.thermalState != .critical else { server.stop(); webState = "温度过高，电脑控制暂停"; return }
        if settings.value.webEnabled && foreground {
            do { try server.start(); webState = "启动中" }
            catch { webState = "启动失败，请检查端口和权限" }
        } else { server.stop(); webState = "关闭" }
    }
    func changePhase(_ phase: ScenePhase) {
        foreground = phase == .active
        analysis.setActive(foreground)
        if phase == .background {
            if recording {
                backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "完成当前录像文件") { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
                    }
                }
            }
            if recording { recordingWarning = "切到后台已停止记录，请回到前台后手动开始。" }
            stop(); server.stop(); webState = "后台暂停"
        } else if phase == .active { applyWebSetting() }
    }
}
