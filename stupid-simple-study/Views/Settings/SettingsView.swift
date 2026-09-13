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
                    Toggle("Focus ratings", isOn: $settings.focusRatingsEnabled)
                    Toggle("Streaks", isOn: $settings.streaksEnabled)
                    Stepper(
                        "Daily goal: \(String(format: "%.1f", settings.dailyGoalHours))h",
                        value: $settings.dailyGoalHours,
                        in: 0.5...12,
                        step: 0.5
                    )
                    .disabled(settings.useWeekdayDailyGoals)
                    Toggle("Different goal per weekday", isOn: $settings.useWeekdayDailyGoals)
                    if settings.useWeekdayDailyGoals {
                        ForEach(0..<7, id: \.self) { index in
                            Stepper(
                                "\(AppSettings.weekdayGoalLabels[index]): \(String(format: "%.1f", settings.weekdayGoalHours[index]))h",
                                value: weekdayGoalBinding(index),
                                in: 0.5...12,
                                step: 0.5
                            )
                        }
                    }
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

    private func weekdayGoalBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { settings.weekdayGoalHours[index] },
            set: { newValue in
                var hours = settings.weekdayGoalHours
                hours[index] = newValue
                settings.weekdayGoalHours = hours
            }
        )
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
