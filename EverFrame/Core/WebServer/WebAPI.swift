import Foundation

@MainActor final class WebAPI {
    unowned let app: AppModel
    let pairing: PairingStore
    init(app: AppModel, pairing: PairingStore) { self.app = app; self.pairing = pairing }
    private func encoded<T: Encodable>(_ value: T) throws -> HTTPResponse {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return HTTPResponse(body: try encoder.encode(value))
    }
    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            guard ProcessInfo.processInfo.thermalState != .critical else { return .json(["error":"设备温度过高，电脑控制已暂停"], status: 503) }
            if request.method == "GET", ["/", "/app.js", "/style.css"].contains(request.path) {
                let name = request.path == "/" ? "index.html" : String(request.path.dropFirst())
                let parts = name.split(separator: ".")
                guard let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) else { return .json(["error":"网页资源不存在"], status: 404) }
                let type = name.hasSuffix("html") ? "text/html" : name.hasSuffix("js") ? "text/javascript" : "text/css"
                return HTTPResponse(type: type + "; charset=utf-8", body: try Data(contentsOf: url))
            }
            if request.method == "POST" {
                guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else { return .json(["error":"只接受 JSON"], status: 400) }
                if let origin = request.headers["origin"], origin != "http://" + (request.headers["host"] ?? "") { return .json(["error":"来源不匹配"], status: 403) }
            }
            if request.path == "/api/pair", request.method == "POST" {
                struct Pair: Decodable { let code: String }
                do { return .json(["token":try pairing.pair(JSONDecoder().decode(Pair.self, from: request.body).code)]) }
                catch { return .json(["error":error.localizedDescription], status: 429) }
            }
            guard pairing.authorized(request.headers["authorization"]) else { return .json(["error":"请先配对"], status: 401) }
            guard app.ready else { return .json(["error":"正在恢复素材"], status: 503) }
            switch (request.method, request.path) {
            case ("GET", "/api/status"):
                return .json(["name":Product.name,"recording":app.recording,"busy":app.busy,"elapsed":app.elapsed,"todaySeconds":app.todaySeconds,"usedBytes":app.storage.usedBytes,"freeBytes":app.storage.freeBytes,"ai":app.analysis.state,"message":app.message])
            case ("POST", "/api/start"):
                guard app.foreground else { return .json(["error":"请先在手机前台打开 App"], status: 409) }
                await app.start()
                return .json(["recording":app.recording,"message":app.message], status: app.recording ? 200 : 409)
            case ("POST", "/api/stop"): app.stop()
            case ("POST", "/api/keep"):
                struct Keep: Decodable { let minutes: Int }
                let value = try JSONDecoder().decode(Keep.self, from: request.body)
                try app.clips.keep(minutes: value.minutes)
            case ("GET", "/api/clips"): return try encoded(Array(app.clips.clips.prefix(500)))
            case ("GET", "/api/timeline"):
                let events = app.timeline.events(clips: app.clips.clips.filter { Calendar.current.isDateInToday($0.startAt) })
                return .json(events.map { ["clipID":$0.clip.id.uuidString,"startAt":ISO8601DateFormatter().string(from: $0.startAt),"endAt":ISO8601DateFormatter().string(from: $0.endAt),"title":$0.event.title,"summary":$0.event.summary,"importance":$0.event.importance_score] as [String: Any] })
            case ("GET", "/api/daily-summary"): return try encoded(app.daily.summaries[DailySummaryRepository.day(Date())])
            case ("POST", "/api/daily-summary"): app.analysis.generateDaily()
            case ("GET", "/api/settings"): return try encoded(app.settings.value)
            case ("POST", "/api/settings"):
                // 网页只允许修改录像/存储参数；AI 隐私授权、Key 和网络启停必须在手机操作。
                struct Update: Decodable { let segmentMinutes: Int; let maxStorageGB: Double; let retentionDays: Int; let minimumFreeGB: Double }
                let patch = try JSONDecoder().decode(Update.self, from: request.body)
                var value = app.settings.value
                value.segmentMinutes = patch.segmentMinutes; value.maxStorageGB = patch.maxStorageGB
                value.retentionDays = patch.retentionDays; value.minimumFreeGB = patch.minimumFreeGB
                try app.updateSettings(value)
            default:
                let parts = request.path.split(separator: "/")
                guard request.method == "POST", parts.count == 4, parts[0] == "api", parts[1] == "clips", let id = UUID(uuidString: String(parts[2])), ["lock","unlock"].contains(parts[3]), app.clips.clips.contains(where: { $0.id == id }) else { return .json(["error":"接口或素材不存在"], status: 404) }
                try app.clips.setLocked(id, parts[3] == "lock")
            }
            AppLogger.shared.log("已配对网页控制操作")
            return .json(["ok":true])
        } catch { return .json(["error":error.localizedDescription], status: 400) }
    }
}
