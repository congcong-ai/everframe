import Foundation
import Combine

// 所有 JSON 写入原子替换；只在主 actor 调用，文件录像由独立 capture queue 写入。
@MainActor final class ClipRepository: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    let root: URL
    let clipsURL: URL
    init(root: URL? = nil) throws {
        let base = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(Product.storageDirectory)
        self.root = base
        clipsURL = base.appendingPathComponent("Clips")
        try FileManager.default.createDirectory(at: clipsURL, withIntermediateDirectories: true)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var backupRoot = base; try backupRoot.setResourceValues(resource)
        try load()
    }
    func url(for clip: Clip) -> URL { clipsURL.appendingPathComponent(clip.fileName) }
    func metadataURL(_ clip: Clip) -> URL { url(for: clip).deletingPathExtension().appendingPathExtension("json") }
    func load() throws {
        clips = []
        let files = FileManager.default.enumerator(at: clipsURL, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }
            do { clips.append(try JSONDecoder().decode(Clip.self, from: Data(contentsOf: url))) }
            catch { AppLogger.shared.log("metadata 损坏，等待录像恢复扫描") }
        }
        clips.sort { $0.startAt > $1.startAt }
    }
    func save(_ clip: Clip) throws {
        let path = metadataURL(clip)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(clip).write(to: path, options: .atomic)
        if let index = clips.firstIndex(where: { $0.id == clip.id }) { clips[index] = clip }
        else { clips.append(clip) }
        clips.sort { $0.startAt > $1.startAt }
    }
    func create() throws -> Clip {
        let now = Date()
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter(); time.dateFormat = "HH-mm-ss-SSS"
        let clip = Clip(fileName: "\(day.string(from: now))/\(time.string(from: now)).mov", startAt: now)
        try save(clip) // 先持久化 pendingLock 的承载对象，再开始写视频。
        return clip
    }
    func setLocked(_ id: UUID, _ locked: Bool) throws {
        guard var clip = clips.first(where: { $0.id == id }) else { return }
        if clip.isWriting { clip.pendingLock = locked } else { clip.locked = locked }
        try save(clip)
    }
    func keep(minutes: Int, now: Date = Date()) throws {
        guard [10, 30, 60].contains(minutes) else { throw AppError.message("保留时长无效") }
        for var clip in clips where clip.overlaps(since: now.addingTimeInterval(Double(-minutes * 60)), until: now) {
            if clip.isWriting { clip.pendingLock = true } else { clip.locked = true }
            try save(clip)
        }
    }
    func delete(_ id: UUID, confirmLocked: Bool = false) throws {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        guard !clip.isWriting, !clip.pendingLock else { throw AppError.message("正在写入或等待保护的录像不能删除") }
        guard !clip.locked || confirmLocked else { throw AppError.message("删除保留素材需要确认") }
        // 先删除视频；失败时仍保留索引和保护状态。
        if FileManager.default.fileExists(atPath: url(for: clip).path) { try FileManager.default.removeItem(at: url(for: clip)) }
        if FileManager.default.fileExists(atPath: metadataURL(clip).path) { try FileManager.default.removeItem(at: metadataURL(clip)) }
        clips.removeAll { $0.id == id }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
