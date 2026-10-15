import Foundation

enum AIJSON {
    static func decode<T: Decodable>(_ type: T.Type, text: String) throws -> T {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            let lines = value.components(separatedBy: .newlines)
            guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else { throw AppError.message("AI JSON 代码块不完整") }
            value = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = value.data(using: .utf8), data.count <= 1_000_000 else { throw AppError.message("AI JSON 过大或无效") }
        return try JSONDecoder().decode(type, from: data)
    }
}
