import AVFoundation
import UIKit
import Observation

/// Live guidance shown on the camera while the farmer frames the leaf.
enum CameraHint: Equatable {
    case searching, good, tooDark, tooBright, blurry
    var titleKey: String {
        switch self {
        case .searching: "cam.hint.searching"; case .good: "cam.hint.good"; case .tooDark: "cam.hint.dark"
        case .tooBright: "cam.hint.bright"; case .blurry: "cam.hint.blur"
        }
    }
    var icon: String {
        switch self {
        case .searching: "viewfinder"; case .good: "checkmark.circle.fill"; case .tooDark: "moon.fill"
        case .tooBright: "sun.max.fill"; case .blurry: "scope"
        }
    }
}

/// AVFoundation camera: live preview, tap-to-focus, torch, still capture and a real-time quality analysis of the video frames
/// (brightness + sharpness, the same maths as `ImageQualityChecker`) so the user is warned *before* taking a poor photo.
@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum State: Equatable { case idle, unauthorized, unavailable, running, failed(String) }

    var state: State = .idle
    var hint: CameraHint = .searching
    var torchOn = false
    var hasTorch = false
    var isCapturing = false

    let session = AVCaptureSession()
    @ObservationIgnored var onPhoto: ((UIImage) -> Void)?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "agrinova.camera.session")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var rotation: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var lastEvaluation = CACurrentMediaTime()
    @ObservationIgnored private var configured = false

    static var isHardwareAvailable: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    // MARK: Lifecycle

    @MainActor func start() async {
        guard Self.isHardwareAvailable else { state = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .unauthorized; return }
        default: state = .unauthorized; return
        }
        do { try configureIfNeeded() } catch { state = .failed(error.localizedDescription); return }
        attachRotationIfReady()
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
        state = .running
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
        setTorch(false)
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else { throw CameraError.noCamera }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else { throw CameraError.cannotConfigure }
        session.addInput(input); session.addOutput(photoOutput)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "agrinova.camera.frames"))
        session.addOutput(videoOutput)
        device = cam; hasTorch = cam.hasTorch; configured = true
    }

    enum CameraError: LocalizedError {
        case noCamera, cannotConfigure
        var errorDescription: String? { tr("cam.unavailable") }
    }

    /// Called by the preview view so photo + preview use the correct rotation on iPhone and iPad (any orientation).
    /// The coordinator needs both the camera device and the preview layer, which become available in either order.
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    func attach(previewLayer: AVCaptureVideoPreviewLayer) { self.previewLayer = previewLayer; attachRotationIfReady() }
    private func attachRotationIfReady() {
        guard rotation == nil, let device, let previewLayer else { return }
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
    }
    var previewAngle: CGFloat { rotation?.videoRotationAngleForHorizonLevelPreview ?? 90 }

    // MARK: Controls

    func capture() {
        guard state == .running, !isCapturing else { return }
        isCapturing = true
        if let angle = rotation?.videoRotationAngleForHorizonLevelCapture, let c = photoOutput.connection(with: .video), c.isVideoRotationAngleSupported(angle) {
            c.videoRotationAngle = angle
        }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
    }

    func toggleTorch() { setTorch(!torchOn) }

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { torchOn = false; return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch { torchOn = false }
    }

    /// `point` is in the capture device's coordinate space (0…1), converted by the preview layer.
    func focus(at point: CGPoint) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point; device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point; device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.isCapturing = false
            if let image { self.onPhoto?(image) } else { self.state = .failed(error?.localizedDescription ?? tr("err.bad_image")) }
        }
    }

    // MARK: Live frame analysis (~3 times per second)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastEvaluation > 0.35, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastEvaluation = now
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixels) > 0, let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pixels, 0), h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let step = max(1, w / 160)
        let ow = w / step, oh = h / step
        guard ow > 4, oh > 4 else { return }
        let luma = base.assumingMemoryBound(to: UInt8.self)
        var gray = [UInt8](repeating: 0, count: ow * oh)
        for y in 0..<oh { for x in 0..<ow { gray[y * ow + x] = luma[(y * step) * stride + x * step] } }
        let report = ImageQualityChecker.assess(gray: gray, width: ow, height: oh)
        let newHint: CameraHint = report.issues.contains(.tooDark) ? .tooDark
            : report.issues.contains(.overexposed) ? .tooBright
            : report.issues.contains(.blurry) ? .blurry : .good
        DispatchQueue.main.async { if self.hint != newHint { self.hint = newHint } }
    }
}
