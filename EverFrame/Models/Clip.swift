import Foundation

enum JobStatus: String, Codable { case pending, running, completed, failed }
struct Clip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var fileName: String
    var createdAt: Date = Date()
    var startAt: Date
    var endAt: Date?
    var duration: Double = 0
    var fileSize: Int64 = 0
    var codec: String = "unknown"
    var width: Int = 1280
    var height: Int = 720
    var fps: Double = 24
    var locked = false
    var pendingLock = false
    var transcriptionStatus: JobStatus = .pending
    var aiStatus: JobStatus = .pending
    var summary: String?
    var importanceScore: Int?
    var failure: String?
    var isWriting: Bool { endAt == nil }
    func overlaps(since: Date, until: Date) -> Bool { startAt <= until && (endAt ?? until) >= since }
}
