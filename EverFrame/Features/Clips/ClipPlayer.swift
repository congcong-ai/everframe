import SwiftUI
import AVKit

struct Playback: Identifiable { let clip: Clip; var offset: Double = 0; var id: UUID { clip.id } }
struct ClipPlayer: View {
    let playback: Playback
    @EnvironmentObject private var repository: ClipRepository
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        NavigationStack {
            VideoPlayer(player: player).navigationTitle(playback.clip.startAt.formatted(date: .omitted, time: .shortened)).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("关闭") { dismiss() } }
                .onAppear {
                    let p = AVPlayer(url: repository.url(for: playback.clip)); player = p
                    p.seek(to: CMTime(seconds: playback.offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
                }.onDisappear { player?.pause(); player = nil }
        }
    }
}
struct ReviewList: View {
    let clips: [Clip]
    @EnvironmentObject private var timeline: TimelineRepository
    @State private var playback: Playback?
    var body: some View {
        List {
            if clips.isEmpty { Text("还没有值得回看的建议。启用 AI 后，已整理的内容会出现在这里。").foregroundColor(.secondary) }
            ForEach(clips) { clip in
                Button { playback = Playback(clip: clip, offset: timeline.analyses[clip.id]?.timeline.max(by: { $0.importance_score < $1.importance_score })?.start ?? 0) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(clip.startAt.formatted(date: .omitted, time: .shortened)) – \((clip.endAt ?? clip.startAt).formatted(date: .omitted, time: .shortened))  ⭐ \(clip.importanceScore ?? 0)").font(.headline)
                        Text(timeline.analyses[clip.id]?.review_reason ?? "").foregroundColor(.secondary)
                    }.padding(.vertical, 8)
                }
            }
        }.sheet(item: $playback) { ClipPlayer(playback: $0) }
    }
}
