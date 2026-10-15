import Foundation

struct AppSettings: Codable, Equatable {
    var segmentMinutes = 10
    var maxStorageGB: Double = 40
    var retentionDays = 7
    var minimumFreeGB: Double = 15
    var aiEnabled = false
    var autoAnalyze = true
    var wifiOnly = true
    var chargingOnly = true
    var allowAppleOnlineSpeech = false
    var model = Product.defaultModel
    var webEnabled = false
    #if DEBUG
    var debugSegmentSeconds: Double = 0
    var debugSmallStorage = false
    var debugForceAI = false
    var debugLowDisk = false
    #endif
    enum CodingKeys: String, CodingKey { case segmentMinutes, maxStorageGB, retentionDays, minimumFreeGB, aiEnabled, autoAnalyze, wifiOnly, chargingOnly, allowAppleOnlineSpeech, model, webEnabled }
    var segmentSeconds: Double {
        #if DEBUG
        if [30.0,60.0].contains(debugSegmentSeconds) { return debugSegmentSeconds }
        #endif
        return Double(segmentMinutes * 60)
    }
    var maxBytes: Int64 {
        #if DEBUG
        if debugSmallStorage { return 300_000_000 }
        #endif
        return Int64(maxStorageGB * 1_000_000_000)
    }
    func validate() throws {
        guard [5,10,15,30].contains(segmentMinutes), (0.3...500).contains(maxStorageGB),
              (1...365).contains(retentionDays), (1...100).contains(minimumFreeGB),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.count < 100 else { throw AppError.message("设置超出允许范围") }
    }
}
