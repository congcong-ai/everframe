import SwiftUI

struct RecorderView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var clips: ClipRepository
    @EnvironmentObject private var timeline: TimelineRepository
    @EnvironmentObject private var analysis: AnalysisQueue
    @EnvironmentObject private var screenPower: RecordingScreenPower
    @State private var details = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !warnings.isEmpty {
                    Button { details = true } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(warningSummaries.joined(separator: " · ")).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                        }.font(.subheadline).padding(12)
                    }
                    .foregroundColor(.primary).background(Color.orange.opacity(0.2))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(warnings.joined(separator: "。") + "。轻点查看完整警告")
                }
                GeometryReader { geometry in
                    ZStack {
                        if app.dualRecording { DualCameraPreview(layer: app.dualEngine.previewLayer) }
                        else { CameraPreview(session: app.engine.session, mirrored: app.cameraPosition == .front) }
                        VStack(spacing: 0) {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Spacer(); previewActions }
                                    recordingBadge
                                }
                            } else {
                                HStack(alignment: .top) { recordingBadge; Spacer(minLength: 4); previewActions }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.dualRecording ? "双录 · 上后下前 · 画面不镜像" : app.cameraPosition == .front ? "前置 · 镜像预览" : "后置摄像头").font(.caption.bold())
                                Text(app.message).font(.footnote).lineLimit(3).accessibilityIdentifier("recordingMessage")
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.black.opacity(0.65)).cornerRadius(12)
                        }.padding(12)
                    }
                    .foregroundColor(.white).background(Color.black)
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls.fixedSize(horizontal: false, vertical: true)
            }
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $details) { detailSheet }
            .alert("前后双录", isPresented: Binding(get: { app.cameraNotice != nil && !details }, set: { if !$0 { app.cameraNotice = nil } })) { Button("知道了", role: .cancel) { app.cameraNotice = nil } } message: { Text(app.cameraNotice ?? "") }
        }
    }

    private var recordingBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(app.recording && !app.canStopRecording ? "正在保存…" : app.cameraSwitching ? "正在切换镜头…" : app.recording ? "REC · 正在记录" : app.busy ? "正在处理…" : "待机", systemImage: app.recording ? "record.circle.fill" : "circle")
                .foregroundColor(app.recording ? .red : .white).font(.subheadline.bold())
            Text(clock(app.elapsed)).font(.system(.title2, design: .monospaced).weight(.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }.padding(12).background(.black.opacity(0.65)).cornerRadius(16)
    }
    private var previewActions: some View {
        HStack(spacing: 8) {
            Button { Task { await app.toggleDualRecording() } } label: {
                VStack(spacing: 2) {
                    Image(systemName: "rectangle.split.1x2").font(.title3)
                    Text("双录").font(.caption2)
                }.padding(6).frame(minWidth: 48, minHeight: 48)
                    .background(app.dualRecording ? Color.everGreen : Color.black.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel(app.dualRecording ? "切回单镜头" : "启用前后双录")
                .disabled(app.busy || !app.ready)
            Button { details = true } label: {
                Image(systemName: "ellipsis").font(.title3.bold()).frame(width: 48, height: 48)
                    .background(.black.opacity(0.65)).clipShape(Circle())
            }.accessibilityLabel("记录详情与状态")
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button { screenPower.dim() } label: {
                Label("屏幕最低亮度", systemImage: "sun.min").font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).accessibilityHint("轻触屏幕恢复；录制中无操作一分钟自动调暗")
            HStack(spacing: 12) {
                Button {
                    if app.recording { app.stop() } else { Task { await app.start() } }
                } label: {
                    Label(app.recording ? (app.canStopRecording ? "停止记录" : "正在保存…") : app.busy ? (app.cameraSwitching ? "正在切换…" : "正在准备…") : "开始记录", systemImage: app.recording ? "stop.fill" : "record.circle")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(app.recording ? .red : .everGreen)
                .disabled(!app.ready || (app.recording ? !app.canStopRecording : app.busy))
                .accessibilityIdentifier("recordingToggle")
                Button { Task { await app.switchCamera() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(minWidth: 52, minHeight: 52)
                }
                .buttonStyle(.bordered).disabled(app.dualRecording || app.busy || app.cameraSwitching || !app.ready)
                .accessibilityLabel("切换到\(app.cameraPosition == .back ? "前置" : "后置")摄像头")
                .accessibilityHint("录制中切换会先保存当前段，再自动续录，可能有短暂间隔")
                .accessibilityIdentifier("switchCamera")
            }
            HStack {
                Menu {
                    ForEach([10, 30, 60], id: \.self) { minutes in
                        Button("保留最近\(minutes)分钟", systemImage: "star") { app.keep(minutes) }
                    }
                } label: {
                    Label("保留最近", systemImage: "star").font(.subheadline.bold()).frame(minHeight: 44)
                }.disabled(!app.ready).accessibilityHint("选择最近10、30或60分钟，保护现有素材")
                Spacer(minLength: 8)
                Text(app.dualRecording ? "双录 · 上后下前" : app.cameraSwitching ? "正在切换，可随时停止" : app.recording ? "切换镜头会自动分段" : "保持前台记录")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.trailing)
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private var detailSheet: some View {
        NavigationStack {
            List {
                if !warnings.isEmpty {
                    Section("需要注意") {
                        ForEach(warnings, id: \.self) { Text($0).foregroundColor(.orange) }
                    }
                }
                Section("记录状态") {
                    Text(app.message)
                    metric("当前连续记录", clock(app.elapsed))
                    metric("今日已记录", durationText(app.todaySeconds))
                    metric("当前摄像头", app.dualRecording ? "前后双录（上后下前）" : app.cameraPosition == .front ? "前置（文件不镜像）" : "后置")
                    Text("录制时可切换镜头：先保存当前段，再切换并自动续录，切换处可能有短暂音画间隔。切换期间仍可停止；停止或切后台后不会自动续录。")
                }
                Section("前后双录") {
                    Text("双录将同步采集的前后画面合成为一个720×1280有声视频，上方后置、下方前置，预览与文件均不镜像。双录会增加功耗与发热，需在兼容真机验收。请停止保存后切换模式。")
                    Button(app.dualRecording ? "切回单镜头" : "启用前后双录") { Task { await app.toggleDualRecording() } }
                        .disabled(app.busy || !app.ready)
                }
                Section("存储与整理") {
                    metric("素材占用", bytesText(app.storage.usedBytes))
                    metric("剩余空间", bytesText(app.storage.freeBytes))
                    metric("AI 已整理至", clips.clips.filter { $0.aiStatus == .completed }.compactMap(\.endAt).max()?.formatted(date: .omitted, time: .shortened) ?? "等待整理")
                    Text(analysis.state)
                }
                Section("保留素材") {
                    ForEach([10, 30, 60], id: \.self) { minutes in
                        Button("保留最近\(minutes)分钟") { app.keep(minutes) }.disabled(!app.ready)
                    }
                    Text("保护与时间窗口相交的整个片段；已循环删除的素材无法恢复。")
                }
                Section {
                    NavigationLink("今天值得回看 · \(reviewClips.count) 个") { ReviewList(clips: reviewClips).navigationTitle("今天值得回看") }
                    Text("录制中无操作1分钟自动降至最低亮度，也可点“屏幕最低亮度”。轻触恢复原亮度，首次触摸不会操作底下的按钮。调暗不等于锁屏；锁屏或切后台仍会停止录像并保存当前文件，返回后需手动开始。")
                }
            }.navigationTitle("记录详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { details = false } }
                .alert("前后双录", isPresented: Binding(get: { app.cameraNotice != nil && details }, set: { if !$0 { app.cameraNotice = nil } })) { Button("知道了", role: .cancel) { app.cameraNotice = nil } } message: { Text(app.cameraNotice ?? "") }
        }
    }
    private var warningSummaries: [String] {
        var result: [String] = []
        if let warning = app.recordingWarning {
            result.append(warning.contains("中断") ? "录像中断" : warning.contains("后台") ? "后台停录" : "录像或镜头异常")
        }
        if app.storageWarning != nil { result.append("存储警告") }
        if app.thermalWarning != nil { result.append("温度警告") }
        return result
    }
    private var warnings: [String] { [app.recordingWarning, app.storageWarning, app.thermalWarning].compactMap { $0 } }
    private var reviewClips: [Clip] { clips.clips.filter { Calendar.current.isDateInToday($0.startAt) && timeline.analyses[$0.id]?.suggested_review == true } }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundColor(.secondary); Text(value).monospacedDigit() }
    }
    private func clock(_ seconds: Double) -> String { let s = Int(seconds); return String(format: "%02d:%02d:%02d", s/3600, s%3600/60, s%60) }
}
func bytesText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
func durationText(_ seconds: Double) -> String { let m = Int(seconds)/60; return "\(m/60)小时\(m%60)分钟" }

// 仅在本应用前台改变亮度；系统锁屏仍由 iOS 管理。
@MainActor final class RecordingScreenPower: ObservableObject {
    private weak var window: UIWindow?
    private var originalBrightness: CGFloat?
    private var cover: UIControl?
    private var idle = RecordingIdleDeadline()
    private var deadline: Timer?
    private var recording = false
    private var active = true

    func attach(_ window: UIWindow) { self.window = window }
    func update(recording: Bool, active: Bool) {
        self.recording = recording; self.active = active
        restore()
    }
    func interaction() {
        deadline?.invalidate(); deadline = nil
        idle.reset(recording: recording && originalBrightness == nil, active: active, now: ProcessInfo.processInfo.systemUptime)
        guard idle.deadline != nil else { return }
        deadline = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.idle.expired(at: ProcessInfo.processInfo.systemUptime) else { return }
                self.dim()
            }
        }
    }
    func dim() {
        guard active, originalBrightness == nil, let window else { return }
        deadline?.invalidate(); deadline = nil
        originalBrightness = window.screen.brightness
        window.screen.brightness = 0
        let cover = UIButton(type: .custom)
        cover.frame = window.bounds
        cover.isAccessibilityElement = true
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .black
        cover.accessibilityLabel = "屏幕已调至最低亮度，轻点恢复"
        cover.accessibilityTraits = .button
        cover.addTarget(self, action: #selector(restore), for: .touchUpInside)
        let label = UILabel()
        label.text = "轻触恢复亮度 · 录制状态不变"
        label.textColor = .lightGray; label.font = .preferredFont(forTextStyle: .footnote)
        label.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: cover.centerXAnchor), label.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
        window.addSubview(cover); self.cover = cover
    }
    @objc func restore() {
        if let brightness = originalBrightness { window?.screen.brightness = brightness }
        originalBrightness = nil; cover?.removeFromSuperview(); cover = nil
        interaction()
    }
}

private final class ScreenTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var activity: (() -> Void)?
    init(activity: @escaping () -> Void) {
        self.activity = activity
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false; delegate = self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { activity?() }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { activity?() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { activity?(); state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { activity?(); state = .failed }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

struct ScreenInteractionObserver: UIViewRepresentable {
    let power: RecordingScreenPower
    final class ObserverView: UIView {
        var power: RecordingScreenPower?
        private var observer: ScreenTouchObserver?
        private weak var observedWindow: UIWindow?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let observer { observedWindow?.removeGestureRecognizer(observer) }
            guard let window, let power else { return }
            power.attach(window)
            let observer = ScreenTouchObserver { [weak power] in power?.interaction() }
            window.addGestureRecognizer(observer)
            observedWindow = window; self.observer = observer
        }
        func detach() {
            if let observer { observedWindow?.removeGestureRecognizer(observer) }
            power?.update(recording: false, active: false)
        }
    }
    func makeUIView(context: Context) -> ObserverView { let view = ObserverView(); view.power = power; view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ uiView: ObserverView, context: Context) {}
    static func dismantleUIView(_ uiView: ObserverView, coordinator: ()) { uiView.detach() }
}
