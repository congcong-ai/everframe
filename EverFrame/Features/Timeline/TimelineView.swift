import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var repository: ClipRepository
    @EnvironmentObject private var timeline: TimelineRepository
    @EnvironmentObject private var daily: DailySummaryRepository
    @EnvironmentObject private var analysis: AnalysisQueue
    @State private var selectedDay = Date()
    @State private var playback: Playback?
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("记录日期", selection: $selectedDay, displayedComponents: .date)
                    Text(analysis.state).font(.caption).foregroundColor(.secondary)
                }
                if let summary = daily.summaries[DailySummaryRepository.day(selectedDay)] {
                    Section("每日总结 · \(durationText(summary.recordedSeconds))") {
                        Text(summary.summary)
                        ForEach(Array(summary.accomplishments.enumerated()), id: \.offset) { Text("\($0.offset + 1). \($0.element)") }
                        ForEach(Array(summary.ideas.enumerated()), id: \.offset) { Label($0.element, systemImage: "lightbulb") }
                        ForEach(Array(summary.reviews.enumerated()), id: \.offset) { item in
                            if let clip = repository.clips.first(where: { $0.id == item.element.clipID }) {
                                Button { playback = Playback(clip: clip) } label: { Label("\(clip.startAt.formatted(date: .omitted, time: .shortened)) · \(item.element.reason)", systemImage: "star") }
                            }
                        }
                    }
                }
                Section("工作时间轴") {
                    let events = timeline.events(clips: repository.clips.filter { Calendar.current.isDate($0.startAt, inSameDayAs: selectedDay) && timeline.matches($0, query: search) })
                    if events.isEmpty { Text("这一天还没有匹配的 AI 时间轴。原始录像始终可在素材页查看。").foregroundColor(.secondary) }
                    ForEach(events) { event in
                        Button { playback = Playback(clip: event.clip, offset: event.event.start) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("\(event.startAt.formatted(date: .omitted, time: .shortened)) – \(event.endAt.formatted(date: .omitted, time: .shortened))"); Spacer(); if event.event.importance_score >= 75 { Text("⭐ \(event.event.importance_score)") } }.font(.caption).foregroundColor(.secondary)
                                Text(event.event.title).font(.headline)
                                Text(event.event.summary).font(.callout).foregroundColor(.secondary)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }.navigationTitle("时间轴").searchable(text: $search, prompt: "搜索工作记忆")
                .toolbar { if Calendar.current.isDateInToday(selectedDay) { Button("生成今日总结") { analysis.generateDaily() } } }
                .sheet(item: $playback) { ClipPlayer(playback: $0) }
        }
    }
}
