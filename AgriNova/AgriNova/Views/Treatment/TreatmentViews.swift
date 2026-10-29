import SwiftUI
import Charts
import PhotosUI
import CoreData

// MARK: - List of treatment plans

struct TreatmentsView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDScan.treatmentStartDate, order: .reverse)], predicate: NSPredicate(format: "treatmentStarted == YES"))
    private var scans: FetchedResults<CDScan>
    @FetchRequest(sortDescriptors: []) private var tasks: FetchedResults<CDTask>
    @Environment(AppRouter.self) private var router

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 18)]

    var body: some View {
        ScrollView {
            if scans.isEmpty {
                EmptyStateView(icon: "cross.case.fill", title: tr("treat.empty"), message: tr("treat.empty_msg"), actionTitle: tr("nav.scan")) { router.go(.scan) }
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(scans) { s in
                        NavigationLink { TreatmentDetailView(scan: s) } label: { card(s) }.buttonStyle(.plain)
                    }
                }.padding(20).readableWidth(1100)
            }
        }
    }

    private func card(_ s: CDScan) -> some View {
        let mine = tasks.filter { $0.scanID == s.id }
        let done = mine.filter(\.done).count
        let frac = mine.isEmpty ? 0 : Double(done) / Double(mine.count)
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.leaf.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: frac).stroke(Theme.heroGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(frac * 100))%").font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.ink)
            }.frame(width: 62, height: 62).animation(.easeOut, value: frac)
            VStack(alignment: .leading, spacing: 5) {
                Text(s.disease?.displayName ?? "").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                Text("\(done)/\(mine.count) \(tr("treat.steps_done"))").font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                if frac >= 1 { Chip(text: tr("treat.completed"), icon: "checkmark.seal.fill") }
                else { Chip(text: tr("treat.in_progress"), icon: "clock.fill", color: Theme.sun) }
            }
            Spacer()
            if let img = s.image { Image(uiImage: img).resizable().scaledToFill().frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
        }.padding(16).softCard(radius: 22)
    }
}

// MARK: - Plan detail: checklist, progress tracking, reminders

struct TreatmentDetailView: View {
    @ObservedObject var scan: CDScan
    @Environment(\.managedObjectContext) private var ctx
    @State private var tab = 0
    @State private var tasks: [CDTask] = []
    @State private var progress: [CDProgress] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var pdfURL: URL?
    @State private var showPDF = false
    @State private var recheckDays: Set<Int> = [3, 7, 14]
    @State private var refresh = 0      // bumped when a task is ticked so the header/progress re-render

    private var disease: Disease? { scan.disease }
    private var doneCount: Int { tasks.filter(\.done).count }

    var body: some View {
        let _ = refresh
        ScrollView {
            VStack(spacing: 20) {
                header
                Picker("", selection: $tab.animation(.spring)) {
                    Text(tr("treat.checklist")).tag(0); Text(tr("treat.progress")).tag(1); Text(tr("treat.reminders")).tag(2)
                }.pickerStyle(.segmented)
                switch tab {
                case 0: checklist
                case 1: progressSection
                default: remindersSection
                }
            }.padding(20).readableWidth(820)
        }
        .background(AppBackground())
        .navigationTitle(tr("treat.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { pdfURL = ReportService.scanReport(scan, in: ctx); showPDF = true } label: { Image(systemName: "doc.richtext") }.accessibilityLabel(tr("pdf.report"))
        } }
        .sheet(isPresented: $showPDF) { if let pdfURL { PDFViewerSheet(url: pdfURL) } }
        .fullScreenCover(isPresented: $showCamera) { LeafCameraView { img in Task { await addCheck(img) } } }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                await addCheck(img); pickerItem = nil
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        tasks = TreatmentService.tasks(for: scan, in: ctx)
        progress = TreatmentService.progress(for: scan, in: ctx)
        recheckDays = Set((scan.recheckDays ?? "3,7,14").split(separator: ",").compactMap { Int($0) })
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 16) {
            if let img = scan.image { Image(uiImage: img).resizable().scaledToFill().frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) }
            VStack(alignment: .leading, spacing: 6) {
                Text(disease?.displayName ?? "").font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                Text("\(doneCount)/\(tasks.count) \(tr("treat.steps_done"))").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                ProgressView(value: tasks.isEmpty ? 0 : Double(doneCount) / Double(tasks.count)).tint(Theme.leaf)
            }
        }.padding(16).softCard()
    }

    // MARK: Checklist
    private var checklist: some View {
        VStack(spacing: 16) {
            ForEach(["organic", "cultural", "chemical"], id: \.self) { cat in
                let items = tasks.filter { $0.category == cat }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("treat.cat.\(cat)"), systemImage: icon(cat)).font(.rounded(.headline, weight: .bold)).foregroundStyle(color(cat))
                        if cat == "chemical" { Banner(kind: .warning, title: tr("treat.chem_warning")) }
                        ForEach(items) { t in TaskRow(task: t) { refresh += 1 } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
                }
            }
            if tasks.isEmpty { EmptyStateView(icon: "checklist", title: tr("treat.no_tasks"), message: "") }
        }
        .sensoryFeedback(.success, trigger: doneCount)
    }

    private func icon(_ c: String) -> String { c == "organic" ? "leaf.fill" : (c == "chemical" ? "flask.fill" : "hammer.fill") }
    private func color(_ c: String) -> Color { c == "organic" ? Theme.leaf : (c == "chemical" ? Theme.danger : Theme.sky) }

    // MARK: Progress
    private var progressSection: some View {
        let trend = TreatmentService.trend(progress)
        return VStack(spacing: 18) {
            if progress.count >= 2 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(tr("treat.trend")).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                        Spacer()
                        switch trend {
                        case .improving: Chip(text: "↓ \(tr("treat.decreasing"))", icon: "arrow.down.right", color: Theme.leaf, filled: true)
                        case .worsening: Chip(text: "↑ \(tr("treat.progressing"))", icon: "arrow.up.right", color: Theme.danger, filled: true)
                        default: Chip(text: tr("treat.steady"), icon: "equal", color: Theme.sun, filled: true)
                        }
                    }
                    Chart(progress) { p in
                        AreaMark(x: .value("Day", Int(p.dayOffset)), y: .value("%", p.affectedPercent))
                            .foregroundStyle(LinearGradient(colors: [Theme.danger.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", Int(p.dayOffset)), y: .value("%", p.affectedPercent))
                            .foregroundStyle(Theme.danger).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        PointMark(x: .value("Day", Int(p.dayOffset)), y: .value("%", p.affectedPercent)).foregroundStyle(Theme.danger)
                            .annotation(position: .top) { Text("\(Int(p.affectedPercent))%").font(.caption2.bold()).foregroundStyle(Theme.ink) }
                    }
                    .chartYScale(domain: 0...100).chartXAxisLabel(tr("treat.day"))
                    .frame(height: 200)
                    .accessibilityLabel(tr("treat.trend"))
                    .accessibilityValue(progress.map { "\(tr("treat.day")) \($0.dayOffset): \(Int($0.affectedPercent))%" }.joined(separator: ", "))
                }.padding(18).softCard()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("treat.timeline")).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                ForEach(Array(progress.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 14) {
                        if let d = p.imageData, let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tr("treat.day")) \(p.dayOffset)  →  \(Int(p.affectedPercent))% \(tr("treat.affected"))").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text((p.date ?? Date()).formatted(date: .abbreviated, time: .omitted)).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        if i > 0 {
                            let delta = p.affectedPercent - progress[i - 1].affectedPercent
                            Label("\(Int(abs(delta)))", systemImage: delta <= 0 ? "arrow.down" : "arrow.up")
                                .font(.rounded(.caption, weight: .bold)).foregroundStyle(delta <= 0 ? Theme.leaf : Theme.danger)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()

            VStack(spacing: 12) {
                Text(tr("treat.add_check")).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                if isAnalyzing { ProgressView(tr("scan.analyzing")).padding() }
                HStack(spacing: 12) {
                    Button { showCamera = true } label: { Label(tr("scan.camera"), systemImage: "camera.fill") }.buttonStyle(PrimaryButtonStyle(compact: true)).disabled(!LeafCameraView.isAvailable || isAnalyzing)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(tr("scan.library"), systemImage: "photo").font(.rounded(.subheadline, weight: .semibold)).padding(.vertical, 10).padding(.horizontal, 16)
                    }.buttonStyle(SoftButtonStyle(radius: 22)).disabled(isAnalyzing)
                }
            }.padding(18).softCard()
        }
    }

    private func addCheck(_ img: UIImage) async {
        isAnalyzing = true
        let pct = await Task.detached { LeafAnalyzer.affectedPercent(img) }.value
        TreatmentService.addProgress(scan: scan, image: img, percent: pct, in: ctx)
        progress = TreatmentService.progress(for: scan, in: ctx)
        isAnalyzing = false
        ToastCenter.shared.show(tr("treat.check_saved"))
    }

    // MARK: Reminders
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("treat.recheck_in")).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                ForEach([3, 7, 14], id: \.self) { d in
                    let on = recheckDays.contains(d)
                    Button {
                        if on { recheckDays.remove(d) } else { recheckDays.insert(d) }
                    } label: {
                        VStack(spacing: 2) { Text("\(d)").font(.system(size: 28, weight: .bold, design: .rounded)); Text(tr("treat.days")).font(.rounded(.caption)) }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(on ? .white : Theme.ink)
                            .background(on ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Button {
                let days = recheckDays.sorted()
                scan.recheckDays = days.map(String.init).joined(separator: ",")
                PersistenceController.shared.save()
                TreatmentService.scheduleRechecks(scan: scan, days: days)
                ToastCenter.shared.show(tr("treat.reminders_set"))
            } label: { Label(tr("treat.set_reminders"), systemImage: "bell.badge.fill") }.buttonStyle(PrimaryButtonStyle())
            Text(tr("treat.reminder_note")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
        }.padding(18).softCard()
    }
}

/// One checklist row. Observes its Core Data task so ticking updates instantly.
private struct TaskRow: View {
    @ObservedObject var task: CDTask
    let onToggle: () -> Void
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { TreatmentService.setDone(task, !task.done) }
            onToggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(task.done ? Theme.leaf : Theme.inkSoft).symbolEffect(.bounce, value: task.done)
                Text(task.title ?? "").font(.rounded(.subheadline)).foregroundStyle(task.done ? Theme.inkSoft : Theme.ink)
                    .strikethrough(task.done).multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title ?? "")
        .accessibilityValue(task.done ? tr("treat.done") : tr("treat.todo"))
        .accessibilityAddTraits(.isButton)
    }
}
