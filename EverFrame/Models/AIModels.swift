import Foundation

struct TranscriptSegment: Codable, Equatable {
    var start: Double
    var end: Double
    var text: String
}
struct Transcript: Codable {
    var clipID: UUID
    var locale = "zh-CN"
    var segments: [TranscriptSegment]
}
struct AIEvent: Codable, Equatable {
    var start: Double
    var end: Double
    var title: String
    var summary: String
    var importance_score: Int
}
struct Idea: Codable, Equatable { var timestamp: Double; var text: String }
struct ClipAnalysis: Codable, Equatable {
    var summary: String
    var topics: [String]
    var importance_score: Int
    var suggested_review: Bool
    var review_reason: String
    var timeline: [AIEvent]
    var ideas: [Idea]
    func validated(duration: Double) throws -> ClipAnalysis {
        guard !summary.isEmpty, (0...100).contains(importance_score), timeline.count <= 100,
              timeline.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= duration + 1 && (0...100).contains($0.importance_score) }),
              ideas.allSatisfy({ $0.timestamp >= 0 && $0.timestamp <= duration + 1 }) else { throw AppError.message("AI JSON 字段或时间范围无效") }
        return self
    }
}
struct TimelineEvent: Identifiable {
    let clip: Clip
    let index: Int
    let event: AIEvent
    var id: String { "\(clip.id)-\(index)" }
    var startAt: Date { clip.startAt.addingTimeInterval(event.start) }
    var endAt: Date { clip.startAt.addingTimeInterval(event.end) }
}
struct DailySummary: Codable, Identifiable {
    var id: String // 本地日历 yyyy-MM-dd
    var generatedAt: Date
    var recordedSeconds: Double
    var summary: String
    var accomplishments: [String]
    var ideas: [String]
    var reviews: [DailyReview]
}
struct DailyReview: Codable { var clipID: UUID; var reason: String }
