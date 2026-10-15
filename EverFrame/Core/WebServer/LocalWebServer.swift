import Foundation
import Network
import Darwin

// listener、clients 仅由 queue 访问；回调在 start 之前配置。
final class LocalWebServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "web.http", qos: .utility)
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    var handler: ((HTTPRequest) async -> HTTPResponse)?
    var stateChanged: ((String) -> Void)?
    func start(port: NWEndpoint.Port = 8080, interface: NWInterface.InterfaceType? = .wifi) throws {
        try queue.sync {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        if let interface { parameters.requiredInterfaceType = interface }
        parameters.includePeerToPeer = false
        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, self.listener === listener else { return }
            switch state {
            case .ready: self.stateChanged?("开启")
            case .failed: self.stateChanged?("启动失败：检查本地网络权限或端口占用"); listener.cancel(); self.listener = nil
            case .waiting: self.stateChanged?("等待 Wi-Fi 或本地网络权限")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.clients.count < 8 else { connection.cancel(); return }
            let id = UUID(); self.clients[id] = connection
            connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 10) { self.close(id) }
            self.receive(connection, id: id, buffer: Data())
        }
        listener.start(queue: queue)
        }
    }
    func stop() {
        queue.async { self.listener?.cancel(); self.listener = nil; self.clients.values.forEach { $0.cancel() }; self.clients.removeAll() }
    }
    private func close(_ id: UUID) { clients.removeValue(forKey: id)?.cancel() }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            guard let self else { return }
            do {
                let bytes = buffer + (data ?? Data())
                if let request = try HTTPParser.parse(bytes) {
                    Task {
                        let response = await self.handler?(request) ?? .json(["error":"服务未就绪"], status: 503)
                        connection.send(content: response.wire(), completion: .contentProcessed { _ in self.queue.async { self.close(id) } })
                    }
                } else if !complete && error == nil { self.receive(connection, id: id, buffer: bytes) }
                else { self.close(id) }
            } catch {
                connection.send(content: HTTPResponse.json(["error":"HTTP 请求无效或过大"], status: 400).wire(), completion: .contentProcessed { _ in self.queue.async { self.close(id) } })
            }
        }
    }
    static var address: String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var cursor = addresses
        while let current = cursor {
            let interface = current.pointee
            defer { cursor = interface.ifa_next }
            guard String(cString: interface.ifa_name) == "en0", let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return "http://\(String(cString: host)):8080" }
        }
        return nil
    }
}
