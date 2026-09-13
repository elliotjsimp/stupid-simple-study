import SwiftUI

struct SidebarNavButton: View {
  let item: SidebarDestination
  let isSelected: Bool
  let accentColor: Color
  let showsLabel: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: item.symbol)
          .frame(width: 20)
        if showsLabel {
          Text(item.title)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .font(.body.weight(isSelected ? .semibold : .regular))
      .foregroundStyle(isSelected ? accentColor : .primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? accentColor.opacity(0.18) : Color.clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct SidebarView: View {
  @Binding var selection: SidebarDestination?
  @Environment(\.appSettings) private var settings

  private var mainDestinations: [SidebarDestination] {
    SidebarDestination.allCases.filter { $0 != .settings }
  }

  private var accent: Color { settings.resolvedAccentColor }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 4) {
          ForEach(mainDestinations) { item in
            SidebarNavButton(
              item: item,
              isSelected: selection == item,
              accentColor: accent,
              showsLabel: true
            ) {
              selection = item
            }
          }
        }
        .padding(8)
      }
      .hiddenVerticalScrollIndicators()

      Divider()

      SidebarNavButton(
        item: .settings,
        isSelected: selection == .settings,
        accentColor: accent,
        showsLabel: true
      ) {
        selection = .settings
      }
      .padding(8)
    }
    .navigationSplitViewColumnWidth(
      min: WindowLayout.sidebarLabeledMin,
      ideal: WindowLayout.sidebarLabeledIdeal,
      max: WindowLayout.sidebarLabeledMax
    )
  }
}
