import SwiftUI
import PhotosUI

struct ScanView: View {
    @Environment(AppRouter.self) private var router
    @State private var vm = ScanViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDZone.name)]) private var zones: FetchedResults<CDZone>
    @State private var pulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                switch vm.phase {
                case .idle: captureCard
                case .analyzing(let step): analyzingCard(step)
                case .done: doneCard
                case .failed(let msg): failedCard(msg)
                case .modelMissing: ModelMissingCard { vm.reset() }
                case .lowQuality: qualityCard
                case .unsupported(let label): unsupportedCard(label)
                }
                tipsCard
            }
            .padding(20).readableWidth(720)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.phase)
        }
        .fullScreenCover(isPresented: $showCamera) {
            LeafCameraView { img in Task { await vm.submit(img, source: "camera") } }
        }
        .onChange(of: pickerItem) { _, item in Task { await vm.load(item); pickerItem = nil } }
        .onAppear { consumePending() }
        .onChange(of: router.pendingImage) { _, _ in consumePending() }
    }

    private func consumePending() {
        guard let img = router.pendingImage else { return }
        router.pendingImage = nil
        Task { await vm.submit(img, source: "sample") }
    }

    // MARK: Capture
    private var captureCard: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Theme.heroGradient).frame(height: 230)
                ForEach(0..<3) { i in
                    Circle().stroke(.white.opacity(0.18), lineWidth: 1.5).frame(width: 90 + CGFloat(i) * 55)
                        .scaleEffect(pulse ? 1.1 : 0.9).animation(.easeInOut(duration: 1.8).repeatForever().delay(Double(i) * 0.25), value: pulse)
                }
                VStack(spacing: 10) {
                    Image(systemName: "leaf.viewfinder").font(.system(size: 56, weight: .light)).foregroundStyle(.white)
                    Text(tr("scan.hero")).font(.rounded(.headline, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text(tr("scan.hero_sub")).font(.rounded(.footnote)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                }.padding(.horizontal, 20)
            }
            .onAppear { pulse = true }

            if !zones.isEmpty {
                HStack {
                    Image(systemName: "square.grid.2x2.fill").foregroundStyle(Theme.leaf)
                    Text(tr("scan.zone")).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Picker("", selection: $vm.selectedZone) {
                        Text(tr("common.none")).tag(CDZone?.none)
                        ForEach(zones) { z in Text(z.displayName).tag(Optional(z)) }
                    }.tint(Theme.leaf)
                }.padding(14).softCard(radius: 18, depth: 6)
            }

            HStack(spacing: 14) {
                Button { showCamera = true } label: {
                    Label(tr("scan.camera"), systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(!LeafCameraView.isAvailable).opacity(LeafCameraView.isAvailable ? 1 : 0.5)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(tr("scan.library"), systemImage: "photo.on.rectangle")
                        .font(.rounded(.headline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                }.buttonStyle(SoftButtonStyle(radius: 26))
            }
            if !LeafCameraView.isAvailable {
                Banner(kind: .info, title: tr("scan.no_camera"), message: tr("scan.no_camera_msg"))
            }
        }
    }

    private func analyzingCard(_ step: Int) -> some View {
        VStack(spacing: 20) {
            ZStack {
                if let img = vm.preview {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.black.opacity(0.25)))
                        .shimmer().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                ProgressView().controlSize(.large).tint(.white)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(ScanViewModel.stepKeys.enumerated()), id: \.offset) { i, key in
                    HStack(spacing: 12) {
                        Image(systemName: i < step ? "checkmark.circle.fill" : (i == step ? "circle.dotted" : "circle"))
                            .foregroundStyle(i <= step ? Theme.leaf : Theme.inkSoft.opacity(0.4))
                            .symbolEffect(.pulse, isActive: i == step)
                        Text(tr(key)).font(.rounded(.subheadline, weight: i == step ? .bold : .regular)).foregroundStyle(i <= step ? Theme.ink : Theme.inkSoft)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
        }
        .accessibilityElement(children: .combine).accessibilityLabel(tr("scan.analyzing"))
    }

    @ViewBuilder private var doneCard: some View {
        if let scan = vm.savedScan {
            ScanResultView(scan: scan, embedded: true, onRescan: { vm.reset() })
        }
    }

    private var qualityCard: some View {
        VStack(spacing: 16) {
            if let img = vm.preview { Image(uiImage: img).resizable().scaledToFill().frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) }
            Banner(kind: .warning, title: tr("scan.quality_title"), message: tr("scan.quality_msg"))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vm.quality?.issues ?? [], id: \.self) { i in
                    Label(tr("scan.q.\(i.rawValue)"), systemImage: i == .blurry ? "scope" : (i == .tooDark ? "moon.fill" : (i == .overexposed ? "sun.max.fill" : "circle.lefthalf.filled")))
                        .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { vm.reset() } label: { Label(tr("scan.retake"), systemImage: "arrow.counterclockwise.camera.fill") }.buttonStyle(PrimaryButtonStyle())
            Button(tr("scan.use_anyway")) { Task { await vm.continueAnyway() } }.font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }.padding(18).softCard()
    }

    private func unsupportedCard(_ label: String) -> some View {
        VStack(spacing: 16) {
            if let img = vm.preview { Image(uiImage: img).resizable().scaledToFill().frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) }
            Banner(kind: .warning, title: tr("scan.unsupported_title"), message: tr("scan.unsupported_msg", label))
            Button { vm.reset() } label: { Label(tr("scan.rescan"), systemImage: "arrow.counterclockwise.camera.fill") }.buttonStyle(PrimaryButtonStyle())
        }.padding(18).softCard()
    }

    private func failedCard(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Banner(kind: .error, title: tr("scan.failed"), message: msg)
            Button(tr("common.retry")) { vm.reset() }.buttonStyle(PrimaryButtonStyle())
        }.padding(18).softCard()
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: tr("scan.tips"))
            ForEach(["scan.tip1", "scan.tip2", "scan.tip3"], id: \.self) { k in
                Label(tr(k), systemImage: "sparkles").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                    .labelStyle(TipLabelStyle())
            }
        }.padding(18).softCard().opacity(vm.phase == .idle ? 1 : 0.0).frame(height: vm.phase == .idle ? nil : 0).clipped()
    }
}

private struct TipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) { configuration.icon.foregroundStyle(Theme.sun); configuration.title }
    }
}

/// Shown when the Core ML model hasn't been added to the project yet.
struct ModelMissingCard: View {
    var onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Banner(kind: .warning, title: tr("err.model_missing_title"), message: tr("err.model_missing"))
            Text("docs/ML_MODEL_GUIDE.md").font(.system(.footnote, design: .monospaced)).padding(10)
                .background(Theme.inkSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Button(tr("common.ok"), action: onDismiss).buttonStyle(PrimaryButtonStyle(compact: true))
        }.padding(18).softCard()
    }
}
