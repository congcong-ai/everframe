import CoreImage

/// 输出竖屏720×1280，上方后置、下方前置；各画面等比填充，文件不镜像。
enum DualCameraCompositor {
    static let width = 720
    static let height = 1280
    static func image(back: CIImage, front: CIImage) -> CIImage {
        let rear = fitted(back, into: CGRect(x: 0, y: 640, width: 720, height: 640))
        let selfie = fitted(front, into: CGRect(x: 0, y: 0, width: 720, height: 640))
        return rear.composited(over: selfie).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }
    private static func fitted(_ image: CIImage, into rect: CGRect) -> CIImage {
        let scale = max(rect.width / image.extent.width, rect.height / image.extent.height)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledExtent = image.extent.applying(transform)
        // 缩放采样前延展边缘，避免非整数缩放在拼接线产生半透明黑边。
        let scaled = image.clampedToExtent().transformed(by: transform)
        return scaled.transformed(by: CGAffineTransform(translationX: rect.midX - scaledExtent.midX, y: rect.midY - scaledExtent.midY)).cropped(to: rect)
    }
}
