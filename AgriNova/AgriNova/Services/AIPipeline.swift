import UIKit
import CoreML
import Vision

// MARK: - Result types

struct Prediction: Hashable { let label: String; let confidence: Double }

struct ScanOutcome {
    let image: UIImage
    let top: [Prediction]
    let disease: Disease?
    let confidence: Double
    let affectedPercent: Double
    let plantLikelihood: Double
    let needsRescan: Bool
}

enum ClassifierError: LocalizedError {
    case modelMissing, badImage, failed(String)
    var errorDescription: String? {
        switch self {
        case .modelMissing: return tr("err.model_missing")
        case .badImage: return tr("err.bad_image")
        case .failed(let m): return m
        }
    }
}

extension UIImage {
    /// Orientation-normalised CGImage so Vision sees the picture the way the user did.
    func normalizedCGImage(maxSide: CGFloat = 1024) -> CGImage? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.cgImage
    }
    func jpegForStorage(maxSide: CGFloat = 900, quality: CGFloat = 0.8) -> Data? {
        guard let cg = normalizedCGImage(maxSide: maxSide) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}

// MARK: - Core ML + Vision classifier

/// Wraps the bundled `AgriNovaLeaf` Core ML image classifier with a Vision request.
/// Everything runs on-device – no network calls.
final class LeafClassifier {
    static let shared = LeafClassifier()
    private var vnModel: VNCoreMLModel?

    /// True once `AgriNovaLeaf.mlpackage` / `.mlmodel` has been added to the app target.
    var isModelAvailable: Bool { loadModel() != nil }

    private func loadModel() -> VNCoreMLModel? {
        if let vnModel { return vnModel }
        guard let url = Bundle.main.url(forResource: "AgriNovaLeaf", withExtension: "mlmodelc") else { return nil }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: cfg)
            vnModel = try VNCoreMLModel(for: ml)
            return vnModel
        } catch {
            print("⚠️ Could not load AgriNovaLeaf: \(error)")
            return nil
        }
    }

    func classify(_ image: UIImage) async throws -> [Prediction] {
        guard let model = loadModel() else { throw ClassifierError.modelMissing }
        guard let cg = image.normalizedCGImage() else { throw ClassifierError.badImage }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .centerCrop
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do {
                    try handler.perform([request])
                    let obs = (request.results as? [VNClassificationObservation]) ?? []
                    let top = obs.prefix(5).map { Prediction(label: $0.identifier, confidence: Double($0.confidence)) }
                    cont.resume(returning: Array(top))
                } catch {
                    cont.resume(throwing: ClassifierError.failed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Vision helpers (plant gate + saliency crop)

enum VisionHelpers {
    /// Uses Apple's built-in Vision classifier to estimate whether the picture contains foliage at all.
    static func plantLikelihood(_ cg: CGImage) -> Double {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return 1 }
        let words = ["plant", "leaf", "foliage", "vegetation", "tree", "herb", "flower", "grass", "crop", "vegetable", "tomato", "produce"]
        let obs = request.results ?? []
        let hit = obs.filter { o in words.contains { o.identifier.lowercased().contains($0) } }.map { Double($0.confidence) }
        return hit.max() ?? 0
    }

    /// Crops to the most salient object (the leaf) using Vision attention-based saliency.
    static func salientCrop(_ cg: CGImage) -> CGImage {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let box = (request.results?.first as? VNSaliencyImageObservation)?.salientObjects?.first?.boundingBox,
              box.width > 0.25, box.height > 0.25 else { return cg }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h).integral
        return cg.cropping(to: rect) ?? cg
    }
}

// MARK: - Affected-area estimator

/// Estimates what share of the visible leaf tissue is discoloured (yellow / brown / necrotic) using HSV colour
/// segmentation on the Vision-cropped leaf. It is used to track a disease's trend between repeat photos,
/// e.g. Day 1 → 37 %, Day 7 → 25 %, Day 14 → 11 %.
enum LeafAnalyzer {
    static func affectedPercent(_ image: UIImage) -> Double {
        guard let full = image.normalizedCGImage(maxSide: 768) else { return 0 }
        let cg = VisionHelpers.salientCrop(full)
        let side = 112
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var healthy = 0, diseased = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let (h, s, v) = hsv(Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255)
            if v < 0.10 { continue }                   // black background
            if s < 0.16 { continue }                   // white / grey background
            if (70...170).contains(h) && s >= 0.22 { healthy += 1 }
            else if h < 70 || h > 330 { diseased += 1 }   // yellow, orange, brown, red-brown
        }
        let total = healthy + diseased
        guard total > 200 else { return 0 }
        return (Double(diseased) / Double(total) * 100).rounded()
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
}

// MARK: - Orchestrator

/// Scan → Vision → Core ML → result. Used by the scanner, the Seed Data console and progress re-checks.
enum ScanPipeline {
    static func run(_ image: UIImage, threshold: Double) async throws -> ScanOutcome {
        let top = try await LeafClassifier.shared.classify(image)
        let best = top.first
        let disease = best.flatMap { DiseaseCatalog.find($0.label) }
        let conf = best?.confidence ?? 0
        let (plant, affected) = await Task.detached(priority: .userInitiated) { () -> (Double, Double) in
            let plant = image.normalizedCGImage().map(VisionHelpers.plantLikelihood) ?? 1
            return (plant, LeafAnalyzer.affectedPercent(image))
        }.value
        return ScanOutcome(image: image, top: top, disease: disease, confidence: conf,
                           affectedPercent: disease?.isHealthy == true ? 0 : affected,
                           plantLikelihood: plant, needsRescan: conf < threshold)
    }
}

// MARK: - Photo quality check

/// Checks sharpness (variance of the Laplacian) and exposure (mean luminance) before classification so users
/// get a warning – and a chance to retake – when the photo is blurry or badly lit.
struct ImageQualityReport: Equatable {
    enum Issue: String { case blurry, tooDark, overexposed, lowContrast }
    var sharpness: Double
    var brightness: Double      // 0...1
    var contrast: Double        // std-dev of luminance, 0...1
    var issues: [Issue]
    var isAcceptable: Bool { issues.isEmpty }
}

enum ImageQualityChecker {
    static let blurThreshold = 40.0
    static let darkThreshold = 0.22
    static let brightThreshold = 0.90
    static let contrastThreshold = 0.06

    static func assess(_ image: UIImage) -> ImageQualityReport {
        guard let cg = image.normalizedCGImage(maxSide: 400) else { return .init(sharpness: 0, brightness: 0, contrast: 0, issues: [.blurry]) }
        let w = 200, h = max(1, Int(200 * Double(cg.height) / Double(max(1, cg.width))))
        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return .init(sharpness: 100, brightness: 0.5, contrast: 0.2, issues: [])
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return assess(gray: gray, width: w, height: h)
    }

    /// Pure function over a grayscale buffer – unit-testable.
    static func assess(gray: [UInt8], width w: Int, height h: Int) -> ImageQualityReport {
        let n = Double(gray.count)
        let mean = gray.reduce(0.0) { $0 + Double($1) } / max(1, n)
        let variance = gray.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / max(1, n)
        let contrast = sqrt(variance) / 255

        // 4-neighbour Laplacian variance (higher = sharper)
        var lapSum = 0.0, lapSq = 0.0, count = 0.0
        if w > 2 && h > 2 {
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let c = Double(gray[y * w + x])
                    let l = Double(gray[(y - 1) * w + x]) + Double(gray[(y + 1) * w + x]) + Double(gray[y * w + x - 1]) + Double(gray[y * w + x + 1]) - 4 * c
                    lapSum += l; lapSq += l * l; count += 1
                }
            }
        }
        let sharp = count > 0 ? (lapSq / count) - pow(lapSum / count, 2) : 0
        let brightness = mean / 255

        var issues: [ImageQualityReport.Issue] = []
        if sharp < blurThreshold { issues.append(.blurry) }
        if brightness < darkThreshold { issues.append(.tooDark) }
        if brightness > brightThreshold { issues.append(.overexposed) }
        if contrast < contrastThreshold && !issues.contains(.tooDark) && !issues.contains(.overexposed) { issues.append(.lowContrast) }
        return .init(sharpness: sharp, brightness: brightness, contrast: contrast, issues: issues)
    }
}
