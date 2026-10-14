import SwiftUI
import SwiftData

@main
struct stupid_simple_studyApp: App {
    @State private var settings = AppSettings.shared
    @State private var termContext = TermContext()
    @State private var sessionEngine = SessionEngine.shared
    @State private var dayClock = StudyDayClock.shared
    @State private var courseEditor = CourseEditorPresenter()

    let sharedModelContainer: ModelContainer

    init() {
        AppModelContainer.removeStoreIfRequested()
        sharedModelContainer = AppModelContainer.make()
    }

    var body: some Scene {
        Window("Stupid Simple Study", id: "main") {
            RootView()
                .environment(\.appSettings, settings)
                .environment(termContext)
                .environment(sessionEngine)
                .environment(dayClock)
                .environment(courseEditor)
                .preferredColorScheme(settings.preferredColorScheme)
                .appAccentColor(settings)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            if settings.showMenuBarItem {
                MenuBarView()
                    .environment(\.appSettings, settings)
                    .environment(termContext)
                    .environment(sessionEngine)
                    .preferredColorScheme(settings.preferredColorScheme)
            }
        } label: {
            if settings.showMenuBarItem {
                MenuBarLabel()
                    .environment(sessionEngine)
                    .environment(\.appSettings, settings)
            }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)
    }
}
