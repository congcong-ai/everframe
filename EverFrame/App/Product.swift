import Foundation

enum Product {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "EverFrame" }
    static let storageDirectory = "EverFrame" // 数据路径固定，改显示名称不迁移已有录像。
    static let deepSeekURL = URL(string: "https://api.deepseek.com/chat/completions")!
    static let defaultModel = "deepseek-flash"
}
