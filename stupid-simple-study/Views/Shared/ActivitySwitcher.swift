import SwiftUI
import SwiftData

struct ActivitySwitcher: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionEngine.self) private var sessionEngine
    @Query(sort: \Activity.name) private var activities: [Activity]

    var large: Bool = false
  @State private var isHovering = false
  @State private var newActivityName = ""

    private var displayName: String {
        sessionEngine.currentActivityName ?? "No activity"
    }

    private var font: Font {
        large ? .title2.weight(.medium) : .body
    }

    var body: some View {
        Group {
            if isHovering && sessionEngine.isActive {
                Menu {
                    Button("None") { sessionEngine.changeActivity(nil) }
                    ForEach(activities, id: \.persistentModelID) { activity in
                        Button(activity.name) { sessionEngine.changeActivity(activity.name) }
                    }
                    Divider()
                    TextField("New activity", text: $newActivityName)
                    Button("Create & select") {
                        let trimmed = newActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if !activities.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                            modelContext.insert(Activity(name: trimmed))
                            try? modelContext.save()
                        }
                        sessionEngine.changeActivity(trimmed)
                        newActivityName = ""
                    }
                } label: {
                    labelContent
                }
                .menuStyle(.borderlessButton)
            } else {
                labelContent
            }
        }
        .onHover { isHovering = $0 }
    }

    private var labelContent: some View {
        HStack(spacing: 6) {
            Text(displayName)
                .font(font)
                .foregroundStyle(.secondary)
            if isHovering && sessionEngine.isActive {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
