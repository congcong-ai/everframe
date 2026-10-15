import AVFoundation
import CoreImage
import UIKit

/// 独立双录管线；普通录像继续使用 MovieRecordingEngine，不在写文件时切换模式。
final class DualRecordingEngine: NSObject, RecordingEngine, AVCaptureDataOutputSynchronizerDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static var isSupported: Bool {
        guard AVCaptureMultiCamSession.isMultiCamSupported,
              let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        return discovery.supportedMultiCamDeviceSets.contains { $0.contains(back) && $0.contains(front) }
    }
    let session: AVCaptureSession = AVCaptureMultiCamSession()
    let previewLayer = AVSampleBufferDisplayLayer()
    var onFinished: ((URL, Error?) -> Void)?
    var onInterruption: (() -> Void)?
    private let queue = DispatchQueue(label: "camera.dual.recording", qos: .userInitiated)
    private let backOutput = AVCaptureVideoDataOutput()
    private let frontOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var configured = false
    private var pool: CVPixelBufferPool?
    private var previewPending = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var durationLimit: Double = 600
    private var finishing = false
    private var lastVideoAt = ProcessInfo.processInfo.systemUptime
    private var lastAudioAt = ProcessInfo.processInfo.systemUptime
    private var wroteVideo = false
    private var wroteAudio = false
    private var recordingURL: URL?

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
        guard Self.isSupported else { throw AppError.message("此设备不支持前后双录") }
        for media in [AVMediaType.video, .audio] {
            guard await AVCaptureDevice.requestAccess(for: media) else { throw AppError.message("请在系统设置允许摄像头和麦克风权限") }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard self.writer == nil, !self.finishing else { throw AppError.message("请等待双录文件保存完成") }
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
                    try AVAudioSession.sharedInstance().setActive(true)
                    if !self.configured { try self.configureSession() }
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    if !self.configured {
                        if self.session.isRunning { self.session.stopRunning() }
                        self.session.beginConfiguration()
                        self.session.inputs.forEach { self.session.removeInput($0) }
                        self.session.outputs.forEach { self.session.removeOutput($0) }
                        self.session.commitConfiguration()
                        self.synchronizer = nil; self.pool = nil
                        try? AVAudioSession.sharedInstance().setActive(false)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    private func configureSession() throws {
        session.beginConfiguration()
        do {
            try addCamera(.back, output: backOutput)
            try addCamera(.front, output: frontOutput)
            guard let microphone = AVCaptureDevice.default(for: .audio) else { throw AppError.message("没有可用麦克风") }
            let input = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(input), session.canAddOutput(audioOutput) else { throw AppError.message("无法配置双录麦克风") }
            session.addInputWithNoConnections(input)
            session.addOutputWithNoConnections(audioOutput)
            try connect(input: input, output: audioOutput, media: .audio)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.commitConfiguration()
        } catch {
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
            throw error
        }
        guard let multi = session as? AVCaptureMultiCamSession, multi.hardwareCost <= 1, multi.systemPressureCost <= 1 else {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
            throw AppError.message("当前双录配置超出设备负荷，请使用单镜头录像")
        }
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                       kCVPixelBufferWidthKey as String: DualCameraCompositor.width,
                                       kCVPixelBufferHeightKey as String: DualCameraCompositor.height,
                                       kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else { throw AppError.message("无法分配双录画面缓冲区") }
        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [backOutput, frontOutput])
        synchronizer?.setDelegate(self, queue: queue)
        configured = true
    }
    private func addCamera(_ position: AVCaptureDevice.Position, output: AVCaptureVideoDataOutput) throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { throw AppError.message("没有可用前后摄像头") }
        let formats = camera.formats.filter {
            let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return $0.isMultiCamSupported && size.width >= 640 && size.width <= 1280 && size.height <= 720 &&
                $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 24 && $0.maxFrameRate >= 24 }
        }
        guard let format = formats.max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) else {
            throw AppError.message("此镜头没有可用的低负荷双录格式，请使用单镜头录像")
        }
        try camera.lockForConfiguration()
        camera.activeFormat = format
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
        camera.unlockForConfiguration()
        let input = try AVCaptureDeviceInput(device: camera)
        input.videoMinFrameDurationOverride = CMTime(value: 1, timescale: 24)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw AppError.message("设备不支持此双录组合") }
        session.addInputWithNoConnections(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        session.addOutputWithNoConnections(output)
        try connect(input: input, output: output, media: .video)
    }
    private func connect(input: AVCaptureDeviceInput, output: AVCaptureOutput, media: AVMediaType) throws {
        guard let port = input.ports.first(where: { $0.mediaType == media }) else { throw AppError.message("双录输入端口不可用") }
        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else { throw AppError.message("无法连接双录输入") }
        session.addConnection(connection)
        if media == .video {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
    func record(to url: URL, duration: Double) {
        queue.async {
            guard self.writer == nil, !self.finishing else { return }
            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
                let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: DualCameraCompositor.width, AVVideoHeightKey: DualCameraCompositor.height,
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000, AVVideoExpectedSourceFrameRateKey: 24]])
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
                video.expectsMediaDataInRealTime = true; audio.expectsMediaDataInRealTime = true
                guard writer.canAdd(video), writer.canAdd(audio) else { throw AppError.message("无法创建双录音视频文件") }
                writer.add(video); writer.add(audio)
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
                guard writer.startWriting() else { throw writer.error ?? AppError.message("无法开始双录文件") }
                self.writer = writer; self.videoInput = video; self.audioInput = audio; self.adaptor = adaptor
                self.startTime = nil; self.durationLimit = duration; self.recordingURL = url
                self.wroteVideo = false; self.wroteAudio = false
                self.lastVideoAt = ProcessInfo.processInfo.systemUptime; self.lastAudioAt = ProcessInfo.processInfo.systemUptime
                self.monitor(writer)
            } catch { self.onFinished?(url, error) }
        }
    }
    func stop() { queue.async { self.finish() } }
    private func monitor(_ expectedWriter: AVAssetWriter) {
        queue.asyncAfter(deadline: .now() + 5) {
            guard self.writer === expectedWriter, !self.finishing else { return }
            if (ProcessInfo.processInfo.systemUptime - self.lastVideoAt) >= 5 || (ProcessInfo.processInfo.systemUptime - self.lastAudioAt) >= 5 {
                self.finish(error: AppError.message("双录画面或麦克风超过5秒未写入，已停止并保留现有文件"))
            } else { self.monitor(expectedWriter) }
        }
    }
    private func finish(error: Error? = nil) {
        guard let writer, let url = recordingURL, !finishing else { return }
        finishing = true
        let trackError = !wroteVideo || !wroteAudio ? AppError.message("双录未收到完整音视频，现有文件保留以便检查") : nil
        let failure = error ?? writer.error ?? trackError
        guard writer.status == .writing, startTime != nil, wroteVideo else {
            if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
            complete(url: url, error: failure ?? AppError.message("双录尚无画面，记录已停止"))
            return
        }
        videoInput?.markAsFinished(); audioInput?.markAsFinished()
        writer.finishWriting {
            self.queue.async {
                self.complete(url: url, error: failure ?? (writer.status == .completed ? nil : writer.error ?? AppError.message("双录文件未正常封装")))
            }
        }
    }
    private func complete(url: URL, error: Error?) {
        writer = nil; videoInput = nil; audioInput = nil; adaptor = nil
        startTime = nil; recordingURL = nil; finishing = false
        onFinished?(url, error)
    }
    func waitUntilStopped() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
    func shutdown() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            try? AVAudioSession.sharedInstance().setActive(false)
            DispatchQueue.main.async { self.previewLayer.flushAndRemoveImage() }
        }
    }
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput data: AVCaptureSynchronizedDataCollection) {
        guard let back = data.synchronizedData(for: backOutput) as? AVCaptureSynchronizedSampleBufferData,
              let front = data.synchronizedData(for: frontOutput) as? AVCaptureSynchronizedSampleBufferData,
              !back.sampleBufferWasDropped, !front.sampleBufferWasDropped,
              let rearBuffer = CMSampleBufferGetImageBuffer(back.sampleBuffer),
              let selfieBuffer = CMSampleBufferGetImageBuffer(front.sampleBuffer), let pool else { return }
        autoreleasepool {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { return }
            context.render(DualCameraCompositor.image(back: CIImage(cvPixelBuffer: rearBuffer), front: CIImage(cvPixelBuffer: selfieBuffer)), to: buffer)
            let timestamp = CMSampleBufferGetPresentationTimeStamp(back.sampleBuffer)
            showPreview(buffer, timestamp: timestamp)
            guard let writer, !finishing else { return }
            if startTime == nil { writer.startSession(atSourceTime: timestamp); startTime = timestamp }
            if writer.status == .failed { finish(error: writer.error); return }
            if let startTime, CMTimeGetSeconds(timestamp - startTime) >= durationLimit { finish(); return }
            if videoInput?.isReadyForMoreMediaData == true {
                if adaptor?.append(buffer, withPresentationTime: timestamp) == true { wroteVideo = true; lastVideoAt = ProcessInfo.processInfo.systemUptime }
                else { finish(error: writer.error ?? AppError.message("双录视频写入失败")) }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let writer, !finishing, let startTime, writer.status == .writing,
              CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= startTime,
              audioInput?.isReadyForMoreMediaData == true else { return }
        if audioInput?.append(sampleBuffer) == true { wroteAudio = true; lastAudioAt = ProcessInfo.processInfo.systemUptime }
        else { finish(error: writer.error ?? AppError.message("双录音频写入失败")) }
    }
    private func showPreview(_ buffer: CVPixelBuffer, timestamp: CMTime) {
        guard !previewPending else { return }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr, let format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 24), presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        previewPending = true
        DispatchQueue.main.async {
            if self.previewLayer.status == .failed { self.previewLayer.flush() }
            if self.previewLayer.isReadyForMoreMediaData { self.previewLayer.enqueue(sample) }
            self.queue.async { self.previewPending = false }
        }
    }
}
