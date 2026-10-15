import AVFoundation

protocol RecordingEngine: AnyObject {
    var session: AVCaptureSession { get }
    var onFinished: ((URL, Error?) -> Void)? { get set }
    var onInterruption: (() -> Void)? { get set }
    func configure(position: AVCaptureDevice.Position) async throws
    func record(to: URL, duration: Double)
    func stop()
    func waitUntilStopped() async
    func shutdown()
}

final class MovieRecordingEngine: NSObject, RecordingEngine, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "camera.recording", qos: .userInitiated)
    private var configured = false
    private var stopAfterStart = false
    private var recordingPending = false
    private var videoInput: AVCaptureDeviceInput?
    var onFinished: ((URL, Error?) -> Void)?
    var onInterruption: (() -> Void)?
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func interrupted() { onInterruption?() }
    @objc private func audioInterrupted(_ note: Notification) {
        if note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue { onInterruption?() }
    }
    func configure(position: AVCaptureDevice.Position) async throws {
        for media in [AVMediaType.video, .audio] {
            let granted = await AVCaptureDevice.requestAccess(for: media)
            guard granted else { throw AppError.message("请在系统设置允许摄像头和麦克风权限") }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard !self.recordingPending, !self.output.isRecording else {
                        throw AppError.message("请先停止记录并等待保存，再切换摄像头")
                    }
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
                    try AVAudioSession.sharedInstance().setActive(true)
                    if !self.configured {
                        try self.configureSession(position: position)
                    } else if self.videoInput?.device.position != position {
                        try self.replaceCamera(position: position)
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    if !self.configured {
                        if self.session.isRunning { self.session.stopRunning() }
                        try? AVAudioSession.sharedInstance().setActive(false)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    // 所有会话变更仅在 camera.recording 串行队列执行；麦克风不参与切换。
    private func cameraInput(position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw AppError.message("没有可用的\(position == .front ? "前置" : "后置")摄像头")
        }
        return try AVCaptureDeviceInput(device: camera)
    }
    private func configureSession(position: AVCaptureDevice.Position) throws {
        let video = try cameraInput(position: position)
        guard let mic = AVCaptureDevice.default(for: .audio) else { throw AppError.message("没有可用麦克风") }
        let audio = try AVCaptureDeviceInput(device: mic)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        do {
            guard session.canAddInput(video) else { throw AppError.message("无法连接摄像头") }
            session.addInput(video)
            guard session.canAddInput(audio) else { throw AppError.message("无法连接麦克风") }
            session.addInput(audio)
            guard session.canAddOutput(output) else { throw AppError.message("设备不支持录像输出") }
            session.addOutput(output)
            try configureVideo(video.device)
            output.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
            videoInput = video
            configured = true
        } catch {
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            videoInput = nil
            throw error
        }
    }
    private func replaceCamera(position: AVCaptureDevice.Position) throws {
        let replacement = try cameraInput(position: position)
        guard let previous = videoInput else { throw AppError.message("摄像头尚未就绪，请重新开始") }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 先放开旧摄像头的格式约束，再选择新设备支持的预设。
        session.sessionPreset = .high
        session.removeInput(previous)
        do {
            guard session.canAddInput(replacement) else { throw AppError.message("无法切换摄像头") }
            session.addInput(replacement)
            try configureVideo(replacement.device)
            videoInput = replacement
        } catch {
            if session.inputs.contains(where: { $0 === replacement }) { session.removeInput(replacement) }
            do {
                guard session.canAddInput(previous) else { throw error }
                session.addInput(previous)
                try configureVideo(previous.device)
            } catch {
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                videoInput = nil; configured = false
                throw AppError.message("切换失败，原摄像头暂时无法恢复。请重新开始记录以重建连接。")
            }
            throw AppError.message("切换失败，仍使用原摄像头。请重试。")
        }
    }
    private func configureVideo(_ camera: AVCaptureDevice) throws {
        // 预设先选定可用格式；仅在该格式支持时设置 24fps，不强行套用后置格式。
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        try camera.lockForConfiguration()
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 24 && $0.maxFrameRate >= 24 }) {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
        }
        camera.unlockForConfiguration()
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            // 文件保持真实方向；只有前置取景预览镜像，避免文字在文件中反转。
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            let codec: AVVideoCodecType = output.availableVideoCodecTypes.contains(.hevc) ? .hevc : .h264
            output.setOutputSettings([AVVideoCodecKey: codec], for: connection)
        }
    }
    func record(to url: URL, duration: Double) {
        queue.async {
            guard !self.recordingPending, !self.output.isRecording else { return }
            self.recordingPending = true
            self.stopAfterStart = false
            self.output.maxRecordedDuration = CMTime(seconds: duration, preferredTimescale: 600)
            self.output.minFreeDiskSpaceLimit = 500_000_000
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }
    func stop() { queue.async { self.stopAfterStart = true; if self.output.isRecording { self.output.stopRecording() } } }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { if self.stopAfterStart && self.output.isRecording { self.output.stopRecording() } }
    }
    func waitUntilStopped() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
    func shutdown() { queue.async { if self.session.isRunning { self.session.stopRunning() }; try? AVAudioSession.sharedInstance().setActive(false) } }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.recordingPending = false
            self.onFinished?(url, error)
        }
    }
}
