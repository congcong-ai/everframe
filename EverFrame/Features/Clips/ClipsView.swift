import SwiftUI

struct ClipsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var repository: ClipRepository
    @EnvironmentObject private var timeline: TimelineRepository
    @EnvironmentObject private var analysis: AnalysisQueue
    @State private var search = ""
    @State private var playback: Playback?
    @State private var deleting: Clip?
    @State private var error: String?
    private var filtered: [Clip] { repository.clips.filter { timeline.matches($0, query: search) } }
    private var days: [Date] { Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.startAt) })).sorted(by: >) }
    var body: some View {
        NavigationStack {
            List {
                if repository.clips.isEmpty { Text("工作记录会保存在这里。开始记录后，App 会自动分段。").foregroundColor(.secondary) }
                ForEach(days, id: \.self) { day in
                    Section(day.formatted(date: .abbreviated, time: .omitted)) {
                        ForEach(filtered.filter { Calendar.current.isDate($0.startAt, inSameDayAs: day) }) { clip in
                            VStack(alignment: .leading, spacing: 10) {
                                Button { playback = Playback(clip: clip) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(clip.startAt.formatted(date: .omitted, time: .shortened)) – \(clip.endAt?.formatted(date: .omitted, time: .shortened) ?? "录制中")").font(.headline)
                                        Text("\(Int(clip.duration / 60))分钟\(Int(clip.duration) % 60)秒 · \(bytesText(clip.fileSize))").font(.caption).foregroundColor(.secondary)
                                    }
                                }.disabled(clip.isWriting || clip.failure != nil)
                                if clip.locked || clip.pendingLock { Label(clip.pendingLock ? "⭐ 本段录完后保留" : "已保留", systemImage: "star.fill").font(.caption).foregroundColor(.orange) }
                                Text("AI：\(status(clip.aiStatus))").font(.caption).foregroundColor(.secondary)
                                if let summary = clip.summary { Text(summary).font(.callout).lineLimit(3) }
                                if let failure = clip.failure { Text(failure).font(.caption).foregroundColor(.red) }
                                HStack {
                                    Button(clip.locked || clip.pendingLock ? "取消保留" : "保留") { action { try repository.setLocked(clip.id, !(clip.locked || clip.pendingLock)) } }
                                    if !clip.isWriting {
                                        ShareLink(item: repository.url(for: clip)) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享或导出原始录像")
                                        Button("重新分析") { analysis.retry(clip.id) }.disabled(clip.failure != nil)
                                        Spacer()
                                        Button(role: .destructive) { deleting = clip } label: { Image(systemName: "trash") }
                                    }
                                }.font(.caption).buttonStyle(.bordered)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }.navigationTitle("素材").searchable(text: $search, prompt: "搜索转写、主题、观点或摘要")
                .sheet(item: $playback) { ClipPlayer(playback: $0) }
                .alert(deleting?.locked == true ? "删除已保留的录像？" : "删除这段录像？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("取消", role: .cancel) { deleting = nil }
                    Button("永久删除", role: .destructive) { if let clip = deleting { action { try app.remove(clip, confirmed: true) } }; deleting = nil }
                } message: { Text("将删除本机原始录像、对应转写和片段 AI 结果，无法恢复。") }
                .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func action(_ block: () throws -> Void) { do { try block() } catch { self.error = error.localizedDescription } }
    private func status(_ value: JobStatus) -> String { switch value { case .pending: return "等待整理"; case .running: return "正在整理"; case .completed: return "已整理"; case .failed: return "失败，可重新分析" } }
}
