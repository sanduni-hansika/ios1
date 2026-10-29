import SwiftUI

struct LibraryView: View {
    @State private var query = ""
    @State private var filter: Pathogen? = nil
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 16)]

    private var items: [Disease] {
        DiseaseCatalog.all.filter { d in
            (filter == nil || d.pathogen == filter) &&
            (query.isEmpty || d.displayName.localizedCaseInsensitiveContains(query) || d.name[0].localizedCaseInsensitiveContains(query) || d.scientific.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("lib.subtitle")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        filterChip(nil, tr("common.all"), "square.grid.2x2.fill", Theme.leaf)
                        ForEach(Pathogen.allCases, id: \.self) { p in filterChip(p, tr(p.titleKey), p.icon, p.color) }
                    }.padding(.vertical, 4)
                }
                if items.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: tr("lib.none"), message: "")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { d in
                            NavigationLink { DiseaseDetailView(disease: d) } label: { DiseaseCard(disease: d) }.buttonStyle(CardPressStyle())
                        }
                    }.animation(.spring(response: 0.45, dampingFraction: 0.85), value: items.map(\.id))
                }
            }.padding(20).readableWidth(1100)
        }
        .searchable(text: $query, prompt: tr("lib.search"))
    }

    private func filterChip(_ p: Pathogen?, _ title: String, _ icon: String, _ color: Color) -> some View {
        let on = filter == p
        return Button { withAnimation(.spring) { filter = p } } label: { Chip(text: title, icon: icon, color: color, filled: on) }
            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Image-led disease card (uses the real leaf photo for the class the model can detect).
struct DiseaseCard: View {
    let disease: Disease
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(disease.imageName).resizable().scaledToFill().frame(height: 210).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                HStack(spacing: 6) {
                    Chip(text: tr(disease.pathogen.titleKey), icon: disease.pathogen.icon, color: .white).environment(\.colorScheme, .dark)
                    if !disease.isHealthy { severityDots }
                }
                Text(disease.displayName).font(.rounded(.headline, weight: .bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            if disease.isHealthy {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.white).padding(8).background(Theme.leaf, in: Circle()).padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(disease.displayName), \(tr(disease.pathogen.titleKey))")
        .accessibilityHint(tr("lib.open_hint"))
    }

    private var severityDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in Circle().fill(i < disease.severity ? Theme.sun : .white.opacity(0.35)).frame(width: 7, height: 7) }
        }.padding(.horizontal, 8).padding(.vertical, 7).background(.black.opacity(0.35), in: Capsule())
    }
}
