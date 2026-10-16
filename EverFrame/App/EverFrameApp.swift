import SwiftUI

@MainActor final class Bootstrap: ObservableObject {
    @Published var model: AppModel?
    @Published var error: String?
    func load() async {
        guard model == nil else { return }
        do { let app = try AppModel(); model = app; await app.prepare() }
        catch { self.error = "无法读取本地配置：\(error.localizedDescription)。请先通过 Finder 导出并备份 App 数据后排查，勿直接卸载。" }
    }
}
@main struct EverFrameApp: App {
    @StateObject private var bootstrap = Bootstrap()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                if let model = bootstrap.model {
                    RootView().environmentObject(model).environmentObject(model.clips).environmentObject(model.timeline).environmentObject(model.daily).environmentObject(model.settings).environmentObject(model.analysis).environmentObject(model.pairing)
                } else if let error = bootstrap.error { VStack(spacing: 20) { Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle); Text(error) }.padding() }
                else { ProgressView("正在恢复本地记录…") }
            }.task { await bootstrap.load() }.onChange(of: phase) { bootstrap.model?.changePhase($0) }
        }
    }
}
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var phase
    @StateObject private var screenPower = RecordingScreenPower()
    var body: some View {
        TabView {
            RecorderView().tabItem { Label("记录", systemImage: "record.circle") }
            TimelineView().tabItem { Label("时间轴", systemImage: "list.bullet.rectangle") }
            ClipsView().tabItem { Label("素材", systemImage: "film") }
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }.tint(.everGreen)
            .environmentObject(screenPower)
            .background(ScreenInteractionObserver(power: screenPower))
            .onChange(of: app.recording) { screenPower.update(recording: $0, active: phase == .active) }
            .onChange(of: phase) { screenPower.update(recording: app.recording, active: $0 == .active) }
            .onDisappear { screenPower.update(recording: false, active: false) }
    }
}
extension Color { static let everGreen = Color(red: 0.08, green: 0.37, blue: 0.28) }
