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
