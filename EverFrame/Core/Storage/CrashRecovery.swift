import Foundation
import AVFoundation

@MainActor enum CrashRecovery {
    static func run(_ repository: ClipRepository) async {
        let fm = FileManager.default
        let known = repository.clips
        for clip in known where !fm.fileExists(atPath: repository.url(for: clip).path) {
            // 开始后尚未真正写文件也可能退出。移除孤立索引，不影响其它录像。
            try? fm.removeItem(at: repository.metadataURL(clip))
        }
        try? repository.load()
        let files = (fm.enumerator(at: repository.clipsURL, includingPropertiesForKeys: [.creationDateKey])?.allObjects as? [URL] ?? []).filter { $0.pathExtension.lowercased() == "mov" }
        for url in files {
            var clip = repository.clips.first { repository.url(for: $0) == url }
            let orphan = clip == nil
            if clip == nil {
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let relative = String(url.path.dropFirst(repository.clipsURL.path.count + 1))
                clip = Clip(fileName: relative, startAt: date)
                clip?.locked = true // metadata 丢失时无法知道原保护状态，保守保留。
            }
            guard var value = clip else { continue }
            if !value.isWriting && !orphan {
                if value.aiStatus == .running { value.aiStatus = .pending }
                if value.transcriptionStatus == .running { value.transcriptionStatus = .pending }
                try? repository.save(value)
                continue
            }
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                guard duration.seconds.isFinite, duration.seconds > 0 else { throw AppError.message("无可用时长") }
                value.duration = duration.seconds
                value.endAt = value.startAt.addingTimeInterval(duration.seconds)
                value.locked = value.locked || value.pendingLock; value.pendingLock = false
                value.fileSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                try repository.save(value)
            } catch {
                value.endAt = Date(); value.locked = true; value.pendingLock = false
                value.failure = "上次异常退出，文件未正常封装；已保留原文件，无法保证可播放"
                value.transcriptionStatus = .failed; value.aiStatus = .failed
                value.fileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                try? repository.save(value)
                AppLogger.shared.log("恢复扫描发现未封装文件，已保护")
            }
        }
    }
}
