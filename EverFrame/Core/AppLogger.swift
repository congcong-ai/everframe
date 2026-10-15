import Foundation
import os

final class AppLogger {
    static let shared = AppLogger()
    private let queue = DispatchQueue(label: "diagnostics", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "recorder", category: "事件")
    var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("diagnostics.log") }
    // 只传固定事件与非内容错误，不传 key、配对码、token、转写或模型原文。
    func log(_ event: String) {
        logger.info("\(event, privacy: .public)")
        queue.async {
            let path = self.url
            if let attr = try? FileManager.default.attributesOfItem(atPath: path.path), (attr[.size] as? Int ?? 0) > 1_000_000 {
                try? FileManager.default.removeItem(at: path)
            }
            let line = Data("\(ISO8601DateFormatter().string(from: Date())) \(event)\n".utf8)
            if !FileManager.default.fileExists(atPath: path.path) { FileManager.default.createFile(atPath: path.path, contents: nil) }
            if let file = try? FileHandle(forWritingTo: path) { defer { try? file.close() }; _ = try? file.seekToEnd(); try? file.write(contentsOf: line) }
        }
    }
}
