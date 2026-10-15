import Foundation
import Combine
import Security

@MainActor final class PairingStore: ObservableObject {
    @Published private(set) var code = ""
    private var sessions: [String: Date] = [:]
    private var failures = 0
    private var blockedUntil = Date.distantPast
    init() { reset() }
    func reset() {
        code = String(format: "%06d", Int.random(in: 0...999999))
        sessions.removeAll(); failures = 0; blockedUntil = .distantPast
    }
    func pair(_ candidate: String) throws -> String {
        guard Date() >= blockedUntil else { throw AppError.message("配对尝试过多，请一分钟后重试") }
        guard candidate == code else {
            failures += 1
            if failures >= 5 { blockedUntil = Date().addingTimeInterval(60); failures = 0 }
            throw AppError.message("配对码错误")
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.message("无法生成安全会话") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        sessions = sessions.filter { $0.value > Date() }
        if sessions.count >= 8, let old = sessions.min(by: { $0.value < $1.value })?.key { sessions[old] = nil }
        sessions[token] = Date().addingTimeInterval(12 * 3600); failures = 0
        return token
    }
    func authorized(_ header: String?) -> Bool {
        guard let header, header.hasPrefix("Bearer "), let expiry = sessions[String(header.dropFirst(7))], expiry > Date() else { return false }
        return true
    }
}
