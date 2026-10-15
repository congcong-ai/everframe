import Foundation

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}
enum HTTPParseError: Error { case malformed, tooLarge }
enum HTTPParser {
    static let maximumBody = 32_768
    static let maximumHeader = 8_192
    static func parse(_ data: Data) throws -> HTTPRequest? {
        guard data.count <= maximumHeader + maximumBody else { throw HTTPParseError.tooLarge }
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maximumHeader { throw HTTPParseError.tooLarge }; return nil
        }
        guard split.lowerBound <= maximumHeader, let text = String(data: data[..<split.lowerBound], encoding: .utf8) else { throw HTTPParseError.malformed }
        let lines = text.components(separatedBy: "\r\n")
        let start = (lines.first ?? "").split(separator: " ")
        guard start.count == 3, ["GET","POST"].contains(String(start[0])), start[2] == "HTTP/1.1", start[1].hasPrefix("/"), !start[1].contains("#") else { throw HTTPParseError.malformed }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { throw HTTPParseError.malformed }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else { throw HTTPParseError.malformed }
            headers[name] = value
        }
        guard headers["host"] != nil, headers["transfer-encoding"] == nil else { throw HTTPParseError.malformed }
        let rawLength = headers["content-length"] ?? "0"
        guard !rawLength.isEmpty, rawLength.allSatisfy({ $0.isASCII && $0.isNumber }), let length = Int(rawLength), length <= maximumBody else { throw HTTPParseError.tooLarge }
        if start[0] == "POST" && headers["content-length"] == nil { throw HTTPParseError.malformed }
        let end = split.upperBound + length
        guard data.count >= end else { return nil }
        guard data.count == end else { throw HTTPParseError.malformed } // 不支持 pipeline，避免歧义。
        let path = String(start[1]).components(separatedBy: "?")[0]
        return HTTPRequest(method: String(start[0]), path: path, headers: headers, body: Data(data[split.upperBound..<end]))
    }
}
struct HTTPResponse {
    var status = 200
    var type = "application/json; charset=utf-8"
    var body: Data
    static func json(_ value: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data)
    }
    func wire() -> Data {
        let reason = [200:"OK",400:"Bad Request",401:"Unauthorized",403:"Forbidden",404:"Not Found",409:"Conflict",413:"Content Too Large",429:"Too Many Requests",500:"Internal Server Error",503:"Unavailable"][status] ?? "Error"
        let headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\n\r\n"
        return Data(headers.utf8) + body
    }
}
