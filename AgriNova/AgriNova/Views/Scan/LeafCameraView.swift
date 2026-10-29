import SwiftUI
import AVFoundation

/// UIKit view that hosts the live `AVCaptureVideoPreviewLayer`.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var model: CameraModel?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let model, let c = previewLayer.connection {
            let angle = model.previewAngle
            if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }   // follows device rotation (iPhone + iPad)
        }
    }

    @objc func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        model?.focus(at: previewLayer.captureDevicePointConverted(fromLayerPoint: p))
    }
}

struct CameraPreview: UIViewRepresentable {
    let model: CameraModel
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = model.session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.model = model
        v.addGestureRecognizer(UITapGestureRecognizer(target: v, action: #selector(PreviewView.tapped(_:))))
        DispatchQueue.main.async { model.attach(previewLayer: v.previewLayer); v.setNeedsLayout() }
        return v
    }
    func updateUIView(_ v: PreviewView, context: Context) { v.setNeedsLayout() }
}

/// Full-screen leaf camera (AVFoundation): live preview, leaf frame guide, real-time lighting / sharpness hint,
/// torch, tap-to-focus and a large shutter button.
struct LeafCameraView: View {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = CameraModel()

    static var isAvailable: Bool { CameraModel.isHardwareAvailable }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.state {
            case .running: live
            case .idle: ProgressView().tint(.white)
            case .unauthorized: message(icon: "camera.fill", title: tr("cam.permission_title"), body: tr("cam.permission_msg"), showSettings: true)
            case .unavailable: message(icon: "video.slash.fill", title: tr("cam.unavailable"), body: tr("scan.no_camera_msg"), showSettings: false)
            case .failed(let m): message(icon: "exclamationmark.triangle.fill", title: tr("scan.failed"), body: m, showSettings: false)
            }
            VStack { topBar; Spacer() }
        }
        .statusBarHidden()
        .task {
            model.onPhoto = { img in onImage(img); dismiss() }
            await model.start()
        }
        .onDisappear { model.stop() }
        .sensoryFeedback(.impact, trigger: model.isCapturing)
    }

    // MARK: Live camera

    private var live: some View {
        ZStack {
            CameraPreview(model: model).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [14, 10])).foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 36).padding(.vertical, 140).allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack {
                Spacer()
                hintChip.padding(.bottom, 18)
                shutter.padding(.bottom, 34)
            }
        }
    }

    private var hintChip: some View {
        let ok = model.hint == .good
        return Label(tr(model.hint.titleKey), systemImage: model.hint.icon)
            .font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background((ok ? Theme.leaf : (model.hint == .searching ? Color.gray : Theme.sun)).opacity(0.9), in: Capsule())
            .animation(.spring(response: 0.3), value: model.hint)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var shutter: some View {
        Button { model.capture() } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 5).frame(width: 82, height: 82)
                Circle().fill(.white).frame(width: 66, height: 66).scaleEffect(model.isCapturing ? 0.85 : 1)
            }
        }
        .disabled(model.isCapturing)
        .accessibilityLabel(tr("cam.shutter"))
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.isCapturing)
    }

    private var topBar: some View {
        HStack {
            roundButton("xmark", label: tr("cam.close")) { dismiss() }
            Spacer()
            if model.hasTorch && model.state == .running {
                roundButton(model.torchOn ? "bolt.fill" : "bolt.slash.fill", label: tr("cam.torch"), tint: model.torchOn ? Theme.sun : .white) { model.toggleTorch() }
            }
        }.padding(.horizontal, 20).padding(.top, 14)
    }

    private func roundButton(_ icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
                .frame(width: 46, height: 46).background(.ultraThinMaterial, in: Circle())
        }.accessibilityLabel(label)
    }

    private func message(icon: String, title: String, body: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(Theme.sun)
            Text(title).font(.rounded(.title3, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(body).font(.rounded(.subheadline)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            if showSettings {
                Button(tr("set.open_settings")) { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
            Button(tr("cam.close")) { dismiss() }.font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }.padding(32)
    }
}
