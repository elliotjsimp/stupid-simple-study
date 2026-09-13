import SwiftUI
import SwiftData

extension View {
    /// Hides vertical scroll indicators while keeping scroll behavior (Settings keeps default indicators).
    func hiddenVerticalScrollIndicators() -> some View {
        scrollIndicators(.hidden, axes: .vertical)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}

struct CoursePill: View {
    @Environment(CourseEditorPresenter.self) private var courseEditor

    let course: Course
    var large: Bool = false
    var allowsEditing: Bool = true

    var body: some View {
        Text(course.name)
            .font(large ? .title3.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, large ? 18 : 10)
            .padding(.vertical, large ? 10 : 4)
            .background(Color(hex: course.colorHex), in: Capsule())
            .foregroundStyle(.white)
            .contentShape(Capsule())
            .help(allowsEditing ? "Edit course" : course.name)
            .highPriorityGesture(TapGesture().onEnded {
                guard allowsEditing else { return }
                courseEditor.presentEdit(course)
            })
    }
}

struct StarRatingView: View {
    @Binding var rating: Int?
    var max: Int = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max, id: \.self) { value in
                Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .onTapGesture { rating = value }
            }
        }
    }
}

struct StaticStarRatingView: View {
    let rating: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(width: 72, alignment: .trailing)
    }
}

struct DurationLabel: View {
    let seconds: Int

    var body: some View {
        Text(DurationFormatters.compactHours(seconds))
            .font(.body.monospacedDigit())
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image("MenuBarIcon")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TermBannerView: View {
    let isNonActive: Bool
    let isConcluded: Bool

    var body: some View {
        if isNonActive {
            Label("You're viewing a different term. Live sessions can only start in the active term.", systemImage: "eye")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        } else if isConcluded {
            Label("This term has concluded.", systemImage: "flag.checkered")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
