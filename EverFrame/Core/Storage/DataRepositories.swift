import Foundation
import Combine

@MainActor final class SettingsRepository: ObservableObject {
    @Published private(set) var value: AppSettings
    private let url: URL
    init(root: URL) throws {
        url = root.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: url.path) {
            value = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
            try value.validate()
        } else { value = AppSettings() }
    }
    func save(_ settings: AppSettings) throws {
        try settings.validate()
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
        value = settings
    }
}
@MainActor final class TimelineRepository: ObservableObject {
    @Published private(set) var analyses: [UUID: ClipAnalysis] = [:]
    @Published private(set) var transcripts: [UUID: Transcript] = [:]
    private let directory: URL
    init(root: URL) throws {
        directory = root.appendingPathComponent("Analysis")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = url.deletingPathExtension().lastPathComponent
            if url.pathExtension == "json", let id = UUID(uuidString: name), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(ClipAnalysis.self, from: data) { analyses[id] = value }
            if url.pathExtension == "transcript", let id = UUID(uuidString: name), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Transcript.self, from: data) { transcripts[id] = value }
        }
    }
    func save(_ transcript: Transcript) throws {
        try JSONEncoder().encode(transcript).write(to: directory.appendingPathComponent("\(transcript.clipID).transcript"), options: .atomic)
        transcripts[transcript.clipID] = transcript
    }
    func save(_ analysis: ClipAnalysis, id: UUID) throws {
        try JSONEncoder().encode(analysis).write(to: directory.appendingPathComponent("\(id).json"), options: .atomic)
        analyses[id] = analysis
    }
    func remove(_ id: UUID) throws {
        for ext in ["json", "transcript"] {
            let file = directory.appendingPathComponent("\(id).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        analyses[id] = nil; transcripts[id] = nil
    }
    func events(clips: [Clip]) -> [TimelineEvent] {
        clips.flatMap { clip in (analyses[clip.id]?.timeline ?? []).enumerated().map { TimelineEvent(clip: clip, index: $0.offset, event: $0.element) } }.sorted { $0.startAt > $1.startAt }
    }
    func matches(_ clip: Clip, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let analysis = analyses[clip.id]
        let text = [clip.summary ?? "", analysis?.topics.joined(separator: " ") ?? "", analysis?.ideas.map(\.text).joined(separator: " ") ?? "", transcripts[clip.id]?.segments.map(\.text).joined(separator: " ") ?? ""].joined(separator: " ")
        return text.localizedCaseInsensitiveContains(query)
    }
}
@MainActor final class DailySummaryRepository: ObservableObject {
    @Published private(set) var summaries: [String: DailySummary] = [:]
    private let directory: URL
    init(root: URL) throws {
        directory = root.appendingPathComponent("DailySummaries")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let summary = try? JSONDecoder().decode(DailySummary.self, from: data) { summaries[summary.id] = summary }
        }
    }
    nonisolated static func day(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    func save(_ summary: DailySummary) throws {
        try JSONEncoder().encode(summary).write(to: directory.appendingPathComponent(summary.id + ".json"), options: .atomic)
        summaries[summary.id] = summary
    }
}
