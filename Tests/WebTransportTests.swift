import Foundation

// 真实 NWListener + URLSession；业务数据为测试夹具，不声称已验证 iPhone 的 WebAPI。
@main struct WebTransportTests {
    @MainActor static func main() async throws {
        let pair = PairingStore()
        let server = LocalWebServer()
        server.handler = { request in
            route(request, pairing: pair)
        }
        try server.start(port: 18080, interface: nil)
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)
        func request(_ path: String, method: String = "GET", token: String? = nil, json: String? = nil) async throws -> (Data, Int) {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:18080" + path)!)
            req.httpMethod = method; req.timeoutInterval = 5
            if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            if let json { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = Data(json.utf8) }
            let (data, response) = try await URLSession.shared.data(for: req)
            return (data, (response as! HTTPURLResponse).statusCode)
        }
        let (_, denied) = try await request("/api/status")
        guard denied == 401 else { throw AppError.message("匿名访问未被拒绝") }
        let (data, paired) = try await request("/api/pair", method: "POST", json: "{\"code\":\"\(pair.code)\"}")
        guard paired == 200, let body = try JSONSerialization.jsonObject(with: data) as? [String:String], let token = body["token"] else { throw AppError.message("配对请求失败") }
        let (status, accepted) = try await request("/api/status", token: token)
        guard accepted == 200, String(decoding: status, as: UTF8.self).contains("recording") else { throw AppError.message("已配对状态请求失败") }
        let (_, changed) = try await request("/api/keep", method: "POST", token: token, json: "{\"minutes\":30}")
        guard changed == 200 else { throw AppError.message("已配对修改请求失败") }
        pair.reset()
        let (_, revoked) = try await request("/api/status", token: token)
        guard revoked == 401 else { throw AppError.message("会话撤销失败") }
        print("通过：真实 HTTP 传输、匿名拒绝、配对、认证读写、令牌撤销（共5项）")
    }
    @MainActor static func route(_ request: HTTPRequest, pairing: PairingStore) -> HTTPResponse {
        if request.path == "/api/pair" {
            let dict = (try? JSONSerialization.jsonObject(with: request.body)) as? [String:String]
            guard let code = dict?["code"], let token = try? pairing.pair(code) else { return .json(["error":"配对失败"], status: 401) }
            return .json(["token":token])
        }
        guard pairing.authorized(request.headers["authorization"]) else { return .json(["error":"请配对"], status: 401) }
        return .json(["recording":false,"ok":true])
    }
}
