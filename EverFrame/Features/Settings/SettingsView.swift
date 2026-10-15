import SwiftUI
import Speech
import CoreImage.CIFilterBuiltins

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsRepository
    @EnvironmentObject private var pairing: PairingStore
    @State private var key = ""
    @State private var feedback = ""
    @State private var testing = false
    @State private var onlineConsent = false
    @State private var logs = false
    @State private var privacy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("录像") {
                    Picker("每段时长", selection: bind(\.segmentMinutes)) { ForEach([5,10,15,30], id: \.self) { Text("\($0)分钟").tag($0) } }
                    Text("后置摄像头 · 720p · 24fps · 麦克风开启 · HEVC 优先。分段时长从下一段开始生效。").font(.caption).foregroundColor(.secondary)
                }
                Section("循环存储") {
                    Stepper("最大素材占用：\(settings.value.maxStorageGB, specifier: "%.0f") GB", value: bind(\.maxStorageGB), in: 1...500, step: 1)
                    Stepper("普通素材保存：\(settings.value.retentionDays)天", value: bind(\.retentionDays), in: 1...365)
                    Stepper("尽量保留系统空间：\(settings.value.minimumFreeGB, specifier: "%.0f") GB", value: bind(\.minimumFreeGB), in: 1...100, step: 1)
                    Text("只删除最老的未保护素材。保护素材过多、无法满足配额时会提示；实际可用空间低于 1 GB 时停止录像。").font(.caption).foregroundColor(.secondary)
                }
                Section("电脑控制 · 仅局域网") {
                    Toggle("开启电脑控制", isOn: bind(\.webEnabled))
                    LabeledContent("状态", value: app.webState)
                    if settings.value.webEnabled {
                        Text(app.webAddress).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        if let image = qr(app.webAddress), app.webAddress.hasPrefix("http") { Image(uiImage: image).interpolation(.none).resizable().frame(width: 160, height: 160).accessibilityLabel("电脑控制网址二维码") }
                        LabeledContent("配对码", value: pairing.code).font(.system(.title3, design: .monospaced))
                        Button("更新配对码并撤销全部电脑会话") { pairing.reset(); feedback = "旧会话已失效" }
                        Text("开启表示允许向同一局域网内你配对的电脑发送状态、磁盘空间和摘要信息。电脑打开以上网址，输入配对码。手机必须保持前台。连接使用局域网 HTTP，请仅在可信 Wi-Fi 上启用，用后关闭。").font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("AI · DeepSeek") {
                    Toggle("启用 AI 分析", isOn: bind(\.aiEnabled))
                    Text("启用后，已录制素材会转写，文字将发送至你配置的 DeepSeek API。原始视频不会发送给 DeepSeek。AI 失败不影响录像。").font(.caption).foregroundColor(.secondary)
                    TextField("模型", text: bind(\.model)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("输入新的 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(KeychainStore.configuredKey == nil ? "尚未配置 Key" : "Key 已配置，存于 Keychain；不会在这里回显").font(.caption).foregroundColor(.secondary)
                    Button("保存 API Key") {
                        do { let value = key.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { feedback = "请输入 Key"; return }; try KeychainStore.save(value); key = ""; feedback = "Key 已保存至 Keychain" }
                        catch { feedback = error.localizedDescription }
                    }
                    Button("删除已保存的 Key", role: .destructive) { do { try KeychainStore.save(""); feedback = "已删除 Keychain 中的 Key；Scheme 环境变量需在 Xcode 单独移除" } catch { feedback = error.localizedDescription } }
                    Button(testing ? "正在测试…" : "测试连接") { testConnection() }.disabled(testing || !settings.value.aiEnabled)
                    Toggle("自动分析已录完的素材", isOn: bind(\.autoAnalyze))
                    Toggle("仅 Wi-Fi", isOn: bind(\.wifiOnly))
                    Toggle("仅充电时分析", isOn: bind(\.chargingOnly))
                    Button("授权 Apple 语音识别") {
                        SFSpeechRecognizer.requestAuthorization { status in DispatchQueue.main.async { feedback = status == .authorized ? "语音识别已授权" : "未获得语音权限，可在系统设置中修改" } }
                    }
                    Toggle("允许 Apple 在线语音识别", isOn: Binding(get: { settings.value.allowAppleOnlineSpeech }, set: { value in
                        if value { onlineConsent = true } else { set(\.allowAppleOnlineSpeech, false) }
                    }))
                    Text("优先使用本地中文识别。如果此设备不支持，本开关开启后音频可能发送至 Apple 服务器，并受到系统限流。默认关闭。").font(.caption).foregroundColor(.secondary)
                }
                Section("隐私与诊断") {
                    Button("隐私说明") { privacy = true }
                    Button("查看诊断日志") { logs = true }
                    ShareLink(item: AppLogger.shared.url) { Label("导出诊断日志", systemImage: "square.and.arrow.up") }
                    Text("日志不包含 API Key、会话令牌、完整转写或 AI 原文。").font(.caption).foregroundColor(.secondary)
                }
                #if DEBUG
                DeveloperSettingsView()
                #endif
                if !feedback.isEmpty { Section("操作结果") { Text(feedback).foregroundColor(.secondary) } }
            }.navigationTitle("设置")
                .alert("同意 Apple 在线识别？", isPresented: $onlineConsent) {
                    Button("取消", role: .cancel) {}
                    Button("同意") { set(\.allowAppleOnlineSpeech, true) }
                } message: { Text("当本地识别不可用时，录像中提取的音频会发送至 Apple 进行语音识别。原始视频不会上传。") }
                .sheet(isPresented: $logs) { NavigationStack { ScrollView { Text((try? String(contentsOf: AppLogger.shared.url, encoding: .utf8)) ?? "尚无日志").font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }.navigationTitle("诊断日志").toolbar { Button("关闭") { logs = false } } } }
                .sheet(isPresented: $privacy) { NavigationStack { ScrollView { Text("视频、转写、时间轴和每日总结保存在本机。\n\n启用 AI 后，仅带时间戳的转写文本发送给你配置的 DeepSeek API；原始视频和关键帧不发送。\n\nApple 语音识别优先在设备本地完成。只有你明确允许在线识别后，才会在本地不支持时向 Apple 发送音频。\n\n局域网网页只向已配对的电脑提供状态、素材信息与摘要，使用明文 HTTP。请只在可信网络启用。\n\n录像保持前台且持续显示 REC。退出前台停止录像，不使用伪后台模式。\n\n删除素材同时删除对应转写和片段分析；已生成的每日总结独立保存。卸载 App 会删除本机录像，请先分享导出。\n\n请尊重工作场所内其他人的知情与隐私。不会在未点击开始时自动录像。").padding() }.navigationTitle("隐私说明").toolbar { Button("关闭") { privacy = false } } } }
        }
    }
    private func bind<T>(_ path: WritableKeyPath<AppSettings,T>) -> Binding<T> { Binding(get: { settings.value[keyPath: path] }, set: { set(path, $0) }) }
    private func set<T>(_ path: WritableKeyPath<AppSettings,T>, _ value: T) {
        var updated = settings.value; updated[keyPath: path] = value
        do { try app.updateSettings(updated) } catch { feedback = error.localizedDescription }
    }
    private func testConnection() {
        guard ProcessInfo.processInfo.thermalState != .serious, ProcessInfo.processInfo.thermalState != .critical else { feedback = "设备温度偏高，请稍后测试"; return }
        guard let configured = KeychainStore.configuredKey else { feedback = "请先保存 API Key"; return }
        testing = true
        Task {
            defer { testing = false }
            do { try await DeepSeekProvider().test(model: settings.value.model, key: configured); feedback = "连接成功" }
            catch { feedback = error.localizedDescription }
        }
    }
    private func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)), from: output.extent.applying(CGAffineTransform(scaleX: 6, y: 6))) else { return nil }
        return UIImage(cgImage: image)
    }
}
#if DEBUG
struct DeveloperSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsRepository
    @EnvironmentObject private var timeline: TimelineRepository
    @State private var json = false
    var body: some View {
        Section("开发者设置 · 仅 Debug") {
            Picker("测试切片", selection: bind(\.debugSegmentSeconds)) { Text("正常时长").tag(0.0); Text("30秒").tag(30.0); Text("1分钟").tag(60.0) }
            Toggle("最大空间 300 MB", isOn: bind(\.debugSmallStorage))
            Toggle("强制 AI（忽略 Wi-Fi／充电条件）", isOn: bind(\.debugForceAI))
            Toggle("模拟低磁盘（安全停止）", isOn: bind(\.debugLowDisk))
            Button("查看本机 AI JSON") { json = true }
            Text("测试参数仅本次启动有效；仍遵守温度限制与 AI 隐私开关。日志入口位于上方。").font(.caption).foregroundColor(.secondary)
        }.sheet(isPresented: $json) { NavigationStack {
            ScrollView {
                let encoder = JSONEncoder()
                Text(String(decoding: (try? encoder.encode(timeline.analyses)) ?? Data(), as: UTF8.self)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding()
            }.navigationTitle("AI JSON · 包含个人内容").toolbar { Button("关闭") { json = false } }
        } }
    }
    private func bind<T>(_ path: WritableKeyPath<AppSettings,T>) -> Binding<T> { Binding(get: { settings.value[keyPath: path] }, set: { value in var updated = settings.value; updated[keyPath: path] = value; do { try app.updateSettings(updated) } catch { app.message = error.localizedDescription } }) }
}
#endif
