import Foundation

// 仅由 AppModel 在主 actor 访问；跨保存与摄像头配置的 await 保留用户的停止意图。
struct RecordingContinuation {
    private(set) var wantsRecording = false
    private(set) var cameraSwitchPending = false

    mutating func start() {
        wantsRecording = true
        cameraSwitchPending = false
    }
    mutating func stop() {
        wantsRecording = false
        cameraSwitchPending = false
    }
    mutating func requestCameraSwitch() -> Bool {
        guard wantsRecording, !cameraSwitchPending else { return false }
        cameraSwitchPending = true
        return true
    }
    mutating func consumeCameraSwitch() -> Bool {
        guard wantsRecording, cameraSwitchPending else { return false }
        cameraSwitchPending = false
        return true
    }
    func shouldContinue(inForeground: Bool) -> Bool {
        wantsRecording && inForeground
    }
}

// 单调时钟上的空闲期限，不受系统时间调整影响。
struct RecordingIdleDeadline {
    private(set) var deadline: TimeInterval?
    mutating func reset(recording: Bool, active: Bool, now: TimeInterval) {
        deadline = recording && active ? now + 60 : nil
    }
    func expired(at now: TimeInterval) -> Bool { deadline.map { now >= $0 } ?? false }
}
