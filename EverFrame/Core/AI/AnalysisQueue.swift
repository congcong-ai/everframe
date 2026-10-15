import Foundation
import UIKit
import Network
import Speech

@MainActor final class AnalysisQueue: ObservableObject {
    @Published private(set) var state = "AI 未启用"
    @Published private(set) var workingID: UUID?
    private let clips: ClipRepository
    private let timeline: TimelineRepository
    private let daily: DailySummaryRepository
    private let settings: SettingsRepository
    private let storage: StorageManager
    private let speech: TranscriptionProvider = AppleSpeechTranscriptionProvider()
    private let ai: AIProvider = DeepSeekProvider()
    private let monitor = NWPathMonitor()
    private var wifi = false
    private var task: Task<Void, Never>?
    private var retryIDs = Set<UUID>()
    private var active = true
    init(clips: ClipRepository, timeline: TimelineRepository, daily: DailySummaryRepository, settings: SettingsRepository, storage: StorageManager) {
        self.clips = clips; self.timeline = timeline; self.daily = daily; self.settings = settings; self.storage = storage
        UIDevice.current.isBatteryMonitoringEnabled = true
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) } }
        monitor.start(queue: DispatchQueue(label: "ai.network", qos: .utility))
    }
    func setActive(_ value: Bool) { active = value; if !value { task?.cancel() } }
    var gate: String? {
        if !active { return "进入后台，AI 已暂停" }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical { return "设备温度偏高，AI分析已暂停，录像继续。" }
        let s = settings.value
        if !s.aiEnabled { return "AI 未启用" }
        #if DEBUG
        if s.debugForceAI { return nil }
        #endif
        if s.wifiOnly && !wifi { return "等待 Wi-Fi" }
        if s.chargingOnly && UIDevice.current.batteryState != .charging && UIDevice.current.batteryState != .full { return "等待接通电源" }
        return nil
    }
    func checkpoint() throws { try Task.checkCancellation(); if let reason = gate { throw AppError.message(reason) } }
    func tick() {
        if let reason = gate { state = reason; task?.cancel(); return }
        guard task == nil else { return }
        guard KeychainStore.configuredKey != nil else { state = "请配置 DeepSeek API Key"; return }
        guard let clip = clips.clips.sorted(by: { $0.startAt < $1.startAt }).first(where: { !$0.isWriting && $0.failure == nil && ($0.aiStatus == .pending && settings.value.autoAnalyze || retryIDs.contains($0.id)) }) else { state = "AI 已整理现有队列"; return }
        if timeline.transcripts[clip.id] == nil && SFSpeechRecognizer.authorizationStatus() != .authorized {
            state = "请在设置中授权 Apple 语音识别"
            return
        }
        retryIDs.remove(clip.id)
        workingID = clip.id; storage.pinned.insert(clip.id)
        task = Task {
            defer { storage.pinned.remove(clip.id); workingID = nil; task = nil }
            do {
                try checkpoint()
                if timeline.transcripts[clip.id] == nil {
                    try update(clip.id) { $0.transcriptionStatus = .running }
                    state = "正在转写"; AppLogger.shared.log("语音转写开始")
                    let transcript = try await speech.transcribe(url: clips.url(for: clip), clipID: clip.id, allowOnline: settings.value.allowAppleOnlineSpeech) { [weak self] in try self?.checkpoint() }
                    try checkpoint(); try timeline.save(transcript)
                    try update(clip.id) { $0.transcriptionStatus = .completed }
                    AppLogger.shared.log("语音转写完成")
                }
                try checkpoint()
                guard let transcript = timeline.transcripts[clip.id], let key = KeychainStore.configuredKey else { throw AppError.message("缺少转写或 API Key") }
                try update(clip.id) { $0.aiStatus = .running }
                state = "正在整理摘要"; AppLogger.shared.log("DeepSeek 分析开始")
                let analysis = try await ai.analyze(transcript: transcript, duration: clip.duration, model: settings.value.model, key: key)
                try checkpoint(); try timeline.save(analysis, id: clip.id)
                try update(clip.id) { $0.aiStatus = .completed; $0.summary = analysis.summary; $0.importanceScore = analysis.importance_score }
                AppLogger.shared.log("DeepSeek 分析完成")
            } catch {
                let paused = Task.isCancelled || gate != nil
                try? update(clip.id) {
                    if $0.transcriptionStatus == .running { $0.transcriptionStatus = paused ? .pending : .failed }
                    $0.aiStatus = paused ? .pending : .failed
                }
                state = paused ? (gate ?? "分析已暂停") : error.localizedDescription
                AppLogger.shared.log(paused ? "AI 队列暂停" : "AI 任务失败，可手动重试")
            }
        }
    }
    private func update(_ id: UUID, action: (inout Clip) -> Void) throws {
        guard var current = clips.clips.first(where: { $0.id == id }) else { throw AppError.message("素材已不存在") }
        action(&current); try clips.save(current)
    }
    func retry(_ id: UUID) { retryIDs.insert(id); tick() }
    func generateDaily() {
        guard task == nil else { state = "请等待当前分析完成"; return }
        do { try checkpoint() } catch { state = error.localizedDescription; return }
        guard let key = KeychainStore.configuredKey else { state = "请配置 DeepSeek API Key"; return }
        task = Task {
            defer { task = nil }
            do {
                state = "正在生成今日总结"
                let today = clips.clips.filter { Calendar.current.isDateInToday($0.startAt) && !$0.isWriting }
                let result = try await ai.summarize(clips: today, analyses: timeline.analyses, model: settings.value.model, key: key)
                try checkpoint(); try daily.save(result); state = "今日总结已保存"
            } catch { state = error.localizedDescription; AppLogger.shared.log("每日总结失败") }
        }
    }
}
