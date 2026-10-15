import Foundation

struct StoragePolicy {
    static func candidates(clips: [Clip], now: Date, settings: AppSettings, free: Int64, pinned: Set<UUID>) -> [UUID] {
        var freeBytes = free
        var used = clips.reduce(Int64(0)) { $0 + $1.fileSize }
        var result: [UUID] = []
        let cutoff = now.addingTimeInterval(Double(-settings.retentionDays * 86400))
        for clip in clips.sorted(by: { $0.startAt < $1.startAt }) {
            guard !clip.isWriting, !clip.locked, !clip.pendingLock, !pinned.contains(clip.id) else { continue }
            if clip.startAt < cutoff || used > settings.maxBytes || freeBytes < Int64(settings.minimumFreeGB * 1_000_000_000) {
                result.append(clip.id); used -= clip.fileSize; freeBytes += clip.fileSize
            }
        }
        return result
    }
}
@MainActor final class StorageManager {
    let clips: ClipRepository
    let timeline: TimelineRepository
    var pinned = Set<UUID>()
    init(clips: ClipRepository, timeline: TimelineRepository) { self.clips = clips; self.timeline = timeline }
    var usedBytes: Int64 { clips.clips.reduce(0) { $0 + $1.fileSize } }
    var freeBytes: Int64 {
        // 使用实际可用空间，不把可能可清理的系统空间当成已经可写的空间。
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: clips.root.path)
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
    func clean(settings: AppSettings) throws {
        for id in StoragePolicy.candidates(clips: clips.clips, now: Date(), settings: settings, free: freeBytes, pinned: pinned) {
            try clips.delete(id)
            try timeline.remove(id)
            AppLogger.shared.log("循环存储清理了一段未保护录像")
        }
    }
    func requireSafeSpace(settings: AppSettings) throws {
        #if DEBUG
        if settings.debugLowDisk { throw AppError.message("模拟低磁盘：录像已安全停止") }
        #endif
        guard freeBytes > 1_000_000_000 else { throw AppError.message("剩余空间低于安全阈值，停止录像；请导出或删除素材") }
    }
}
