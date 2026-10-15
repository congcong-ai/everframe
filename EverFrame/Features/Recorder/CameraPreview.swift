import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var mirrored = false
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = preview.connection else { return }
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.mirrored = mirrored
        uiView.setNeedsLayout()
    }
}

struct DualCameraPreview: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    final class PreviewView: UIView {
        let display: AVSampleBufferDisplayLayer
        init(display: AVSampleBufferDisplayLayer) {
            self.display = display
            super.init(frame: .zero)
            display.videoGravity = .resizeAspect
            layer.addSublayer(display)
        }
        required init?(coder: NSCoder) { fatalError("不支持从归档加载预览") }
        override func layoutSubviews() { super.layoutSubviews(); display.frame = bounds }
    }
    func makeUIView(context: Context) -> PreviewView { PreviewView(display: layer) }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
