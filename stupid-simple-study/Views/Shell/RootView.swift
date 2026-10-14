import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    @Environment(TermContext.self) private var termContext
    @Environment(SessionEngine.self) private var sessionEngine
    @Environment(StudyDayClock.self) private var dayClock
    @Environment(CourseEditorPresenter.self) private var courseEditor

    @Query(sort: \Term.firstDay) private var terms: [Term]

    @State private var selection: SidebarDestination? = .dashboard
    @State private var showStartSheet = false
    @State private var showEndSheet = false
    @State private var showShortSessionConfirm = false
    @State private var showRecoveryDialog = false
    @State private var pendingSnapshot: SessionSnapshot?

    var body: some View {
        @Bindable var courseEditor = courseEditor
        Group {
            if sessionEngine.focusedMode && sessionEngine.isActive {
                FocusedSessionView(
                    showEndSheet: $showEndSheet,
                    showShortSessionConfirm: $showShortSessionConfirm,
                    onExitToDashboard: { selection = .dashboard }
                )
            } else {
                mainSplit
            }
        }
        .windowContentMinSize(
            width: WindowLayout.minWidth,
            height: WindowLayout.minHeight,
            colorScheme: settings.preferredColorScheme
        )
        .preferredColorScheme(settings.preferredColorScheme)
        .appAccentColor(settings)
        .onChange(of: terms) { _, newTerms in
            termContext.refresh(terms: newTerms)
        }
        .onChange(of: dayClock.startOfToday) { _, _ in
            let wasViewingActive = termContext.activeTerm?.persistentModelID == termContext.displayedTerm?.persistentModelID
            termContext.refresh(terms: terms)
            if wasViewingActive, let active = termContext.activeTerm {
                termContext.selectDisplayedTerm(active)
            }
        }
        .onAppear {
            termContext.refresh(terms: terms)
            if let snapshot = sessionEngine.loadSnapshotIfNeeded() {
                pendingSnapshot = snapshot
                showRecoveryDialog = true
            }
            presentEndSheetIfRequested()
        }
        .onChange(of: sessionEngine.shouldPresentEndSheet) { _, _ in
            presentEndSheetIfRequested()
        }
        .sheet(isPresented: $showEndSheet) {
            EndSessionSheet(isPresented: $showEndSheet)
        }
        .sheet(isPresented: $courseEditor.isPresented) {
            CourseEditorSheet(
                mode: courseEditor.mode,
                isPresented: $courseEditor.isPresented,
                onCreated: { course in
                    courseEditor.onCreated?(course)
                }
            )
        }
        .confirmationDialog("Study time is under 1 minute.", isPresented: $showShortSessionConfirm) {
            Button("Log anyway") {
                sessionEngine.pauseForEnd()
                showEndSheet = true
            }
            Button("Discard", role: .destructive) {
                sessionEngine.discard()
            }
            Button("Keep Going", role: .cancel) {}
        }
        .confirmationDialog(
            "Looks like you quit the app while a session was active",
            isPresented: $showRecoveryDialog,
            titleVisibility: .visible
        ) {
            Button("Resume") {
                if let snapshot = pendingSnapshot {
                    sessionEngine.restore(from: snapshot, context: modelContext, continuing: true)
                }
                pendingSnapshot = nil
            }
            Button("Save as-is") {
                if let snapshot = pendingSnapshot {
                    sessionEngine.restore(from: snapshot, context: modelContext, continuing: false)
                    _ = sessionEngine.saveAsIs(context: modelContext)
                    try? modelContext.save()
                }
                pendingSnapshot = nil
            }
            Button("Discard", role: .destructive) {
                sessionEngine.discard()
                pendingSnapshot = nil
            }
        }
    }

    private var mainSplit: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                if selection == .settings {
                    Text("Settings")
                        .font(.title.weight(.bold))
                        .padding(.bottom, 4)
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        Text(selection?.title ?? "Dashboard")
                            .font(.title.weight(.bold))

                        TermNavigatorView()

                        Spacer()

                        ActiveSessionPill(
                            showStartSheet: $showStartSheet,
                            showEndSheet: $showEndSheet,
                            showShortSessionConfirm: $showShortSessionConfirm
                        )
                    }
                    .padding(.bottom, 4)

                    TermBannerView(
                        isNonActive: termContext.isBrowsingNonActiveTerm,
                        isConcluded: displayedTermHasConcluded && !termContext.isBrowsingNonActiveTerm
                    )
                }
                detailContent
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationSplitViewColumnWidth(min: WindowLayout.detailMinWidth, ideal: WindowLayout.detailIdealWidth)
            .navigationTitle("")
            .toolbar(removing: .title)
        }
        .navigationSplitViewStyle(.balanced)
        .appAccentColor(settings)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .dashboard:
            DashboardView(
                onStartSession: { showStartSheet = true },
                onGoToTerm: { selection = .term }
            )
        case .sessions:
            SessionsView()
        case .term:
            TermView()
        case .settings:
            SettingsView()
        case .none:
            DashboardView(
                onStartSession: { showStartSheet = true },
                onGoToTerm: { selection = .term }
            )
        }
    }

    private var displayedTermHasConcluded: Bool {
        guard let term = termContext.displayedTerm else { return false }
        return term.lastDay < dayClock.startOfToday
    }

    private func presentEndSheetIfRequested() {
        guard sessionEngine.shouldPresentEndSheet else { return }
        showEndSheet = true
        sessionEngine.clearEndSheetPresentationRequest()
    }
}

#Preview {
    RootView()
        .modelContainer(AppModelContainer.make(inMemory: true))
        .environment(TermContext())
        .environment(SessionEngine.shared)
        .environment(StudyDayClock.shared)
        .environment(CourseEditorPresenter())
        .environment(\.appSettings, AppSettings.shared)
}
