import SwiftUI

struct DiseaseDetailView: View {
    let disease: Disease
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var method = 0
    @State private var testing: Int?
    @State private var showCheck = false

    private var steps: [(String, [String], String, Color)] {
        [(tr("treat.cat.organic"), disease.organic, "leaf.fill", Theme.leaf),
         (tr("treat.cat.chemical"), disease.chemical, "flask.fill", Theme.danger),
         (tr("treat.cat.cultural"), disease.cultural, "hammer.fill", Theme.sky)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                parallaxHeader
                VStack(spacing: 20) {
                    overview
                    if hSize == .regular { HStack(alignment: .top, spacing: 20) { symptoms; conditions } } else { symptoms; conditions }
                    if !disease.isHealthy { treatment }
                    prevention
                    gallery
                    Button { router.go(.scan) } label: { Label(tr("lib.scan_cta"), systemImage: "camera.viewfinder") }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(20).readableWidth(900)
                .background(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32).fill(Theme.canvas).ignoresSafeArea(edges: .bottom))
                .offset(y: -28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Header
    private var parallaxHeader: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let h = 340 + max(0, minY)
            ZStack(alignment: .bottomLeading) {
                Image(disease.imageName).resizable().scaledToFill().frame(width: geo.size.width, height: h).clipped()
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Chip(text: tr(disease.pathogen.titleKey), icon: disease.pathogen.icon, color: disease.pathogen.color, filled: true)
                        if disease.isHealthy { StatusBadge(isHealthy: true) } else { Chip(text: tr("lib.severity.\(disease.severity)"), icon: "gauge.medium", color: Theme.sun, filled: true) }
                    }
                    Text(disease.displayName).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    if !disease.isHealthy { Text(disease.scientific).font(.rounded(.subheadline)).italic().foregroundStyle(.white.opacity(0.85)) }
                }.padding(.horizontal, 22).padding(.bottom, 52)
            }
            .frame(width: geo.size.width, height: h).offset(y: -max(0, minY))
        }
        .frame(height: 340)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("lib.about")).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            Text(disease.displaySummary).font(.rounded(.body)).foregroundStyle(Theme.inkSoft)
            if !disease.isHealthy {
                Label { Text(disease.spread).font(.rounded(.subheadline)).foregroundStyle(Theme.ink) } icon: { Image(systemName: "wind").foregroundStyle(Theme.sky) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private var symptoms: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("lib.symptoms")).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            ForEach(disease.symptoms, id: \.self) { s in
                Label { Text(s).font(.rounded(.subheadline)).foregroundStyle(Theme.ink) } icon: {
                    Image(systemName: disease.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(disease.isHealthy ? Theme.leaf : Theme.danger)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("lib.conditions")).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            Label { Text(disease.conditions).font(.rounded(.subheadline)).foregroundStyle(Theme.ink) } icon: { Image(systemName: "cloud.rain.fill").foregroundStyle(Theme.sky) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private var treatment: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("lib.treatment")).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            Picker("", selection: $method.animation(.spring)) {
                ForEach(0..<3, id: \.self) { i in Text(steps[i].0).tag(i) }
            }.pickerStyle(.segmented)
            ForEach(Array(steps[method].1.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").font(.rounded(.footnote, weight: .bold)).foregroundStyle(.white).frame(width: 26, height: 26).background(steps[method].3, in: Circle())
                    Text(s).font(.rounded(.subheadline)).foregroundStyle(Theme.ink)
                }.transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            if method == 1 { Banner(kind: .warning, title: tr("treat.chem_warning")) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private var prevention: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("lib.prevention")).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            ForEach(disease.prevention, id: \.self) { s in
                Label { Text(s).font(.rounded(.subheadline)).foregroundStyle(Theme.ink) } icon: { Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.leaf) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    /// Extra real sample photos – tap one to run it through the on-device Core ML model.
    private var gallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("lib.samples")).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            Text(tr("lib.samples_hint")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach([0, 1, 2], id: \.self) { n in
                        if let img = disease.sampleImage(n) {
                            Button {
                                router.pendingImage = img; router.go(.scan)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    Image(systemName: "wand.and.stars").foregroundStyle(.white).padding(8).background(Theme.leaf, in: Circle()).padding(8)
                                }
                            }.buttonStyle(CardPressStyle()).accessibilityLabel(tr("lib.test_sample"))
                        }
                    }
                }
            }
        }.padding(18).softCard()
    }
}
