import SwiftUI
import Observation
import PhotosUI

@MainActor @Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case idle
        case analyzing(step: Int)
        case done(UUID)               // saved scan id
        case failed(String)
        case modelMissing
        case lowQuality
        case unsupported(String)        // model recognised a non-tomato class (or something else)
        static func == (l: Phase, r: Phase) -> Bool {
            switch (l, r) {
            case (.idle, .idle), (.modelMissing, .modelMissing), (.lowQuality, .lowQuality): true
            case (.unsupported(let a), .unsupported(let b)): a == b
            case (.analyzing(let a), .analyzing(let b)): a == b
            case (.done(let a), .done(let b)): a == b
            case (.failed(let a), .failed(let b)): a == b
            default: false
            }
        }
    }

    var phase: Phase = .idle
    var preview: UIImage?
    var savedScan: CDScan?
    var selectedZone: CDZone?
    var quality: ImageQualityReport?
    private var pendingSource = "camera"

    static let stepKeys = ["scan.step.prepare", "scan.step.species", "scan.step.health", "scan.step.match"]

    /// Entry point for new photos: checks sharpness / lighting first and warns before running the model.
    func submit(_ image: UIImage, source: String) async {
        preview = image; pendingSource = source
        guard source != "sample" else { await analyze(image, source: source); return }   // bundled lab photos skip the check
        let report = await Task.detached(priority: .userInitiated) { ImageQualityChecker.assess(image) }.value
        quality = report
        if report.isAcceptable { await analyze(image, source: source) }
        else { phase = .lowQuality; ToastCenter.shared.show(tr("scan.quality_toast"), kind: .warning) }
    }

    /// "Use this photo anyway" after a quality warning.
    func continueAnyway() async { if let p = preview { await analyze(p, source: pendingSource) } }

    func analyze(_ image: UIImage, source: String) async {
        preview = image
        guard LeafClassifier.shared.isModelAvailable else { phase = .modelMissing; return }
        phase = .analyzing(step: 0)
        // Short staged progress so users see what happens; the real inference runs in parallel.
        let ticker = Task { @MainActor in
            for i in 1..<Self.stepKeys.count {
                try? await Task.sleep(for: .milliseconds(450))
                if case .analyzing = self.phase { self.phase = .analyzing(step: i) }
            }
        }
        do {
            let outcome = try await ScanPipeline.run(image, threshold: AppSettings.shared.confidenceThreshold)
            ticker.cancel()
            // A pre-trained 38-class PlantVillage model may recognise other crops; AgriNova diagnoses tomato only (scope of the proposal).
            if outcome.disease == nil {
                phase = .unsupported(Self.readable(outcome.top.first?.label ?? "?"))
                return
            }
            let scan = ScanStore.save(outcome, source: source, zone: selectedZone)
            savedScan = scan
            if outcome.needsRescan {
                ToastCenter.shared.show(tr("scan.low_toast"), kind: .warning)
            } else {
                ToastCenter.shared.show(tr("scan.done_toast"))
            }
            phase = .done(scan.id ?? UUID())
        } catch ClassifierError.modelMissing {
            ticker.cancel(); phase = .modelMissing
        } catch {
            ticker.cancel(); phase = .failed(error.localizedDescription)
            ToastCenter.shared.show(tr("scan.failed_toast"), kind: .error)
        }
    }

    /// "Apple___Apple_scab" → "Apple – Apple scab"
    static func readable(_ label: String) -> String {
        label.replacingOccurrences(of: "___", with: " – ").replacingOccurrences(of: "_", with: " ")
    }

    func reset() { phase = .idle; preview = nil; savedScan = nil }

    func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        phase = .analyzing(step: 0)
        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
            await submit(img, source: "library")
        } else {
            phase = .failed(tr("err.bad_image"))
        }
    }
}
