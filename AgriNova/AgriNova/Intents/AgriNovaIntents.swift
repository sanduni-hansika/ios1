import AppIntents

/// Siri / Shortcuts integration with App Intents (the modern replacement for SiriKit intent definitions).
/// Say: "Hey Siri, scan a leaf with AgriNova", "Check fungal risk in AgriNova", "What's my last scan in AgriNova".

struct ScanLeafIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a leaf"
    static var description = IntentDescription("Opens the AgriNova scanner so you can photograph a leaf.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.go(.scan)
        return .result()
    }
}

struct LastScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Last scan result"
    static var description = IntentDescription("Reads out your most recent leaf scan.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = SharedStore.load()
        guard let healthy = s.lastScanHealthy else { return .result(dialog: "You have no scans yet. Say scan a leaf to begin.") }
        let pct = Int(s.lastScanConfidence * 100)
        return .result(dialog: IntentDialog(stringLiteral: healthy
            ? "Your last scan looked healthy with \(pct) percent confidence."
            : "Your last scan found \(s.lastScanTitle) with \(pct) percent confidence."))
    }
}

struct FungalRiskIntent: AppIntent {
    static var title: LocalizedStringResource = "Check fungal risk"
    static var description = IntentDescription("Tells you the fungal infection risk for the next three days.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = SharedStore.load()
        let weather = s.temperature.map { " It is \(Int($0)) degrees with \(Int(s.humidity ?? 0)) percent humidity." } ?? ""
        return .result(dialog: IntentDialog(stringLiteral: "Fungal infection risk is \(s.fungalRisk).\(weather)"))
    }
}

struct PendingTreatmentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Pending treatments"
    static var description = IntentDescription("How many treatment steps are still open.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = SharedStore.load()
        return .result(dialog: IntentDialog(stringLiteral: s.pendingTasks == 0 ? "No treatment steps are pending." : "You have \(s.pendingTasks) treatment steps to complete."))
    }
}

struct OutbreakRadarIntent: AppIntent {
    static var title: LocalizedStringResource = "Open outbreak radar"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.go(.radar)
        return .result()
    }
}

struct AgriNovaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanLeafIntent(), phrases: ["Scan a leaf with \(.applicationName)", "Open \(.applicationName) scanner"], shortTitle: "Scan leaf", systemImageName: "camera.viewfinder")
        AppShortcut(intent: LastScanIntent(), phrases: ["Last scan in \(.applicationName)", "What was my last \(.applicationName) scan"], shortTitle: "Last scan", systemImageName: "leaf.fill")
        AppShortcut(intent: FungalRiskIntent(), phrases: ["Check fungal risk in \(.applicationName)", "Disease risk in \(.applicationName)"], shortTitle: "Fungal risk", systemImageName: "cloud.rain.fill")
        AppShortcut(intent: PendingTreatmentsIntent(), phrases: ["Pending treatments in \(.applicationName)"], shortTitle: "Treatments", systemImageName: "cross.case.fill")
        AppShortcut(intent: OutbreakRadarIntent(), phrases: ["Open outbreak radar in \(.applicationName)"], shortTitle: "Outbreak radar", systemImageName: "dot.radiowaves.left.and.right")
    }
}
