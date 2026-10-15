import Foundation
import AVFoundation
import Speech

protocol TranscriptionProvider {
    func transcribe(url: URL, clipID: UUID, allowOnline: Bool, checkpoint: @escaping () async throws -> Void) async throws -> Transcript
}
protocol FrameExtractor { func extract(url: URL, seconds: [Double]) async throws -> [Data] }

final class AppleSpeechTranscriptionProvider: TranscriptionProvider {
    func transcribe(url: URL, clipID: UUID, allowOnline: Bool, checkpoint: @escaping () async throws -> Void) async throws -> Transcript {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw AppError.message("请先在设置页授权语音识别") }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else { throw AppError.message("中文语音识别当前不可用") }
        guard recognizer.supportsOnDeviceRecognition || allowOnline else { throw AppError.message("此设备不支持本地中文识别；可在设置中同意 Apple 在线识别") }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw AppError.message("录像中没有可识别的音轨") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Speech").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        var segments: [TranscriptSegment] = []
        // 每段 55 秒，规避在线识别单次约一分钟限制；时间戳恢复到原录像。
        for start in stride(from: 0.0, to: duration, by: 55.0) {
            try await checkpoint(); try Task.checkCancellation()
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("无法提取音频") }
            let chunkURL = temp.appendingPathComponent("\(Int(start)).m4a")
            exporter.outputURL = chunkURL; exporter.outputFileType = .m4a
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: min(55, duration - start), preferredTimescale: 600))
            await exporter.export()
            guard exporter.status == .completed else { throw AppError.message("音频提取失败") }
            try await checkpoint(); try Task.checkCancellation()
            let request = SFSpeechURLRecognitionRequest(url: chunkURL)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.taskHint = .dictation
            let job = SpeechJob()
            let result = try await withTaskCancellationHandler(operation: { try await job.run(recognizer, request: request) }, onCancel: { job.cancel() })
            segments += result.map { TranscriptSegment(start: start + $0.start, end: min(duration, start + $0.end), text: $0.text) }
            try? FileManager.default.removeItem(at: chunkURL)
        }
        return Transcript(clipID: clipID, segments: segments)
    }
}

// Speech 回调、超时、Task 取消竞争时只能恢复一次 continuation。
private final class SpeechJob: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[TranscriptSegment], Error>?
    private var task: SFSpeechRecognitionTask?
    private var ended = false
    func run(_ recognizer: SFSpeechRecognizer, request: SFSpeechURLRecognitionRequest) async throws -> [TranscriptSegment] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if ended { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            lock.unlock()
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    self.finish(.success(result.bestTranscription.segments.map { TranscriptSegment(start: $0.timestamp, end: $0.timestamp + $0.duration, text: $0.substring) }))
                } else if error != nil { self.finish(.failure(AppError.message("Apple 语音识别失败或已被限流，请稍后重试"))) }
            }
            lock.lock(); self.task = task; let cancelNow = ended; lock.unlock()
            if cancelNow { task.cancel() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90) { self.finish(.failure(AppError.message("语音识别超时"))) }
        }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<[TranscriptSegment], Error>) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true; let continuation = self.continuation; self.continuation = nil; let task = self.task
        lock.unlock()
        task?.cancel(); continuation?.resume(with: result)
    }
}
