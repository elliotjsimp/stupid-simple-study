import SwiftUI
import SwiftData

struct SettingsMenuRow<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                ForEach(options, id: \.0) { value, label in
                    Button {
                        selection = value
                    } label: {
                        if selection == value {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(options.first { $0.0 == selection }?.1 ?? "")
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    @Environment(TermContext.self) private var termContext
    @Environment(SessionEngine.self) private var sessionEngine

    @Query(sort: \Term.firstDay) private var terms: [Term]

    @State private var showImportWarning = false
    @State private var showResetConfirm = false
    @State private var showResetAppDataConfirm = false
    @State private var importError: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    SettingsMenuRow(
                        title: "Appearance",
                        selection: $settings.appearance,
                        options: AppAppearance.allCases.map { ($0, $0.label) }
                    )
                    SettingsMenuRow(
                        title: "Accent color",
                        selection: $settings.accentColor,
                        options: AccentColorPreset.allCases.map { ($0, $0.label) }
                    )
                    Toggle("Show menu bar item", isOn: $settings.showMenuBarItem)
                    Toggle("Show menu bar timer", isOn: $settings.showMenuBarTimer)
                    Toggle("Quality ratings", isOn: $settings.focusRatingsEnabled)
                    Toggle("Streaks", isOn: $settings.streaksEnabled)
                    Toggle("Show goal summary", isOn: $settings.showGoalSummary)
                }

                Section("Goals") {
                    if settings.useWeekdayDailyGoals {
                        WeekdayGoalsGrid(
                            hours: settings.weekdayGoalHours,
                            setHours: { index, hours in
                                var updated = settings.weekdayGoalHours
                                updated[index] = hours
                                settings.weekdayGoalHours = updated
                            }
                        )
                    } else {
                        Stepper(
                            "Daily goal: \(String(format: "%.1f", settings.dailyGoalHours))h",
                            value: $settings.dailyGoalHours,
                            in: 0.5...12,
                            step: 0.5
                        )
                    }
                    Toggle("Different goal per weekday", isOn: $settings.useWeekdayDailyGoals)
                    Stepper(
                        "Heatmap full color at: \(String(format: "%.1f", settings.heatmapFullHours))h",
                        value: $settings.heatmapFullHours,
                        in: 0.5...16,
                        step: 0.5
                    )
                }

                Section("Data") {
                    Button("Export JSONL") {
                        JSONLImportExport.exportAll(context: modelContext)
                    }
                    Button("Import JSONL") {
                        if JSONLImportExport.hasLocalData(context: modelContext) {
                            showImportWarning = true
                        } else {
                            importData()
                        }
                    }
                    Button("Reset sessions (active term)", role: .destructive) {
                        showResetConfirm = true
                    }
                    if let importError {
                        Text(importError).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Reset App Data", role: .destructive) {
                        showResetAppDataConfirm = true
                    }
                } footer: {
                    Text("Deletes all terms, courses, sessions, activities, and settings, then relaunches the app. This cannot be undone.")
                }
            }
            .id("\(settings.appearance.rawValue)-\(settings.preferredColorScheme == .dark ? "dark" : "light")")
            .frame(maxHeight: .infinity, alignment: .top)

            Text("Made by EJS with ❤️")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .onChange(of: settings.useWeekdayDailyGoals) { _, enabled in
            if enabled && settings.weekdayGoalHours.allSatisfy({ $0 == settings.weekdayGoalHours.first }) {
                settings.weekdayGoalHours = Array(repeating: settings.dailyGoalHours, count: 7)
            }
        }
        .confirmationDialog("Import will replace all local data.", isPresented: $showImportWarning) {
            Button("Override", role: .destructive) { importData() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete all sessions for the active term?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                if let term = termContext.activeTerm {
                    try? JSONLImportExport.resetSessionsForTerm(term, context: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Reset all app data?",
            isPresented: $showResetAppDataConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset and Relaunch", role: .destructive) {
                resetAppDataAndRelaunch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all study data, terms, courses, activities, and settings, then relaunches the app. Export your data first if you want to keep a backup.")
        }
    }

    private func resetAppDataAndRelaunch() {
        sessionEngine.discard()
        do {
            try JSONLImportExport.resetAllAppData(context: modelContext)
        } catch {
            importError = "Reset failed: \(error.localizedDescription)"
            return
        }
        settings.resetAllPreferences()
        termContext.refresh(terms: [])
        AppModelContainer.requestStoreWipeOnNextLaunch()
        AppRelauncher.relaunch()
    }

    private func importData() {
        JSONLImportExport.importReplace(context: modelContext, termContext: termContext) { result in
            switch result {
            case .success:
                importError = nil
                termContext.refresh(terms: terms)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }
}

private struct WeekdayGoalsGrid: View {
    let hours: [Double]
    let setHours: (Int, Double) -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                ForEach(0..<7, id: \.self) { index in
                    Text(AppSettings.weekdayGoalShortLabels[index])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            GridRow {
                ForEach(0..<7, id: \.self) { index in
                    Text(hourLabel(index))
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: .infinity)
                }
            }
            GridRow {
                ForEach(0..<7, id: \.self) { index in
                    Stepper(value: hourBinding(index), in: 0.5...12, step: 0.5) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func hourLabel(_ index: Int) -> String {
        String(format: "%.1f", hours.indices.contains(index) ? hours[index] : 2)
    }

    private func hourBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { hours.indices.contains(index) ? hours[index] : 2 },
            set: { setHours(index, $0) }
        )
    }
}
