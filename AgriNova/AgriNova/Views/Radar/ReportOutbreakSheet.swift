import SwiftUI
import CoreLocation

/// Form to share an outbreak with nearby farmers and agricultural extension officers.
/// Works offline: the report is queued in Core Data and uploaded when connectivity returns.
struct ReportOutbreakSheet: View {
    @State var disease: Disease
    var scan: CDScan? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(SyncService.self) private var sync
    @State private var severity = 2
    @State private var notes = ""
    @State private var share = true
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        Image(disease.imageName).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(disease.displayName).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                            Chip(text: tr(disease.pathogen.titleKey), icon: disease.pathogen.icon, color: disease.pathogen.color)
                        }
                        Spacer()
                    }.padding(16).softCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("radar.severity")).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                        Picker("", selection: $severity) {
                            Text(tr("radar.sev.1")).tag(1); Text(tr("radar.sev.2")).tag(2); Text(tr("radar.sev.3")).tag(3)
                        }.pickerStyle(.segmented)
                        Text(tr("radar.notes")).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 6)
                        TextField(tr("radar.notes_ph"), text: $notes, axis: .vertical).lineLimit(3...5).padding(12)
                            .background(Theme.inkSoft.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Toggle(isOn: $share) { Label(tr("radar.share_extension"), systemImage: "person.badge.shield.checkmark.fill").font(.rounded(.subheadline)) }.tint(Theme.leaf)
                        HStack { Image(systemName: "location.fill").foregroundStyle(Theme.sky)
                            Text(location.hasFix ? String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude) : tr("radar.default_loc"))
                                .font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft) }
                    }.padding(16).softCard()

                    if !sync.isOnline { Banner(kind: .info, title: tr("radar.offline_title"), message: tr("radar.offline_msg")) }

                    Button { submit() } label: { Label(tr("radar.submit"), systemImage: "paperplane.fill") }
                        .buttonStyle(PrimaryButtonStyle(gradient: Theme.dangerGradient)).disabled(submitted)
                }.padding(20).readableWidth(620)
            }
            .background(AppBackground())
            .navigationTitle(tr("radar.report")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } } }
            .sensoryFeedback(.success, trigger: submitted)
        }
        .presentationDetents([.large])
    }

    private func submit() {
        let coord = scan.flatMap { $0.hasLocation ? CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) : nil } ?? location.coordinate
        SyncService.shared.submitReport(disease: disease, severity: severity, notes: notes, shareWithExtension: share, coordinate: coord)
        submitted = true
        ToastCenter.shared.show(sync.isOnline ? tr("radar.sent") : tr("radar.queued"), kind: sync.isOnline ? .success : .info)
        dismiss()
    }
}
