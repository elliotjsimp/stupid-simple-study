import AppKit
import SwiftUI

enum WindowLayout {
    static let minWidth: CGFloat = 1000
    static let minHeight: CGFloat = 650
    static let sidebarIconWidth: CGFloat = 52
    static let sidebarLabeledMin: CGFloat = 160
    static let sidebarLabeledIdeal: CGFloat = 200
    static let sidebarLabeledMax: CGFloat = 240
    static let detailMinWidth: CGFloat = minWidth - sidebarLabeledMax
    static let detailIdealWidth: CGFloat = 900
}

private enum WindowChromeSupport {
    /// Stops `NSHostingView` from overwriting `contentMinSize` from SwiftUI layout probes.
    static func suppressHostingViewWindowSizing(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        guard NSStringFromClass(type(of: contentView)).contains("NSHostingView") else { return }
        (contentView as NSObject).setValue(NSHostingSizingOptions(), forKey: "sizingOptions")
    }

    static func applyContentMinimumSize(_ size: CGSize, to window: NSWindow) {
        guard size.width > 0, size.height > 0 else { return }
        suppressHostingViewWindowSizing(in: window)
        if window.contentMinSize != size {
            window.contentMinSize = size
        }
        let frameMin = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        if window.minSize != frameMin {
            window.minSize = frameMin
        }
    }
}

private final class WindowChromeView: NSView {
    var minSize: CGSize = .zero {
        didSet { applyMinimumSize() }
    }

    var colorScheme: ColorScheme = .light {
        didSet { applyAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        DispatchQueue.main.async { [weak self] in
            self?.applyMinimumSize()
        }
    }

    override func layout() {
        super.layout()
        applyMinimumSize()
    }

    func apply() {
        applyMinimumSize()
        applyAppearance()
    }

    private func applyMinimumSize() {
        guard let window else { return }
        WindowChromeSupport.applyContentMinimumSize(minSize, to: window)
    }

    private func applyAppearance() {
        guard let window else { return }
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if window.appearance?.name != appearanceName {
            window.appearance = NSAppearance(named: appearanceName)
        }
    }
}

private struct WindowChromeSetter: NSViewRepresentable {
    var minSize: CGSize
    var colorScheme: ColorScheme

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView()
        view.minSize = minSize
        view.colorScheme = colorScheme
        return view
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {
        nsView.minSize = minSize
        nsView.colorScheme = colorScheme
        nsView.apply()
    }
}

extension View {
    func windowContentMinSize(width: CGFloat, height: CGFloat, colorScheme: ColorScheme) -> some View {
        background(
            WindowChromeSetter(
                minSize: CGSize(width: width, height: height),
                colorScheme: colorScheme
            )
        )
    }
}

struct TermNavigatorView: View {
    @Environment(TermContext.self) private var termContext
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if isHovering && termContext.canNavigateBackward {
                Button {
                    termContext.navigateTerm(forward: false)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
            } else if isHovering {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.tertiary)
            }

            Text(termContext.displayedTerm?.name ?? "No Term")
                .font(.title2.bold())
                .foregroundStyle(.secondary)

            if isHovering && termContext.canNavigateForward {
                Button {
                    termContext.navigateTerm(forward: true)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            } else if isHovering {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

enum SessionControlSize {
    case compact
    case large

    var iconFont: Font {
        switch self {
        case .compact: .body
        case .large: .title2
        }
    }

    var timeFont: Font {
        switch self {
        case .compact: .body.monospacedDigit().weight(.semibold)
        case .large: .system(size: 72, weight: .light, design: .rounded)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: 10
        case .large: 20
        }
    }
}

struct SessionActiveControls: View {
    @Environment(SessionEngine.self) private var sessionEngine

    @Binding var showEndSheet: Bool
    @Binding var showShortSessionConfirm: Bool
    var size: SessionControlSize
    var showsFocusToggle: Bool = true
    var onExitFocusMode: (() -> Void)? = nil

    var body: some View {
        let _ = sessionEngine.tickCount
        return HStack(spacing: size.spacing) {
            if showsFocusToggle {
                Button {
                    sessionEngine.toggleFocusedMode()
                } label: {
                    Image(systemName: sessionEngine.focusedMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(size.iconFont)
                }
                .buttonStyle(.plain)
                .help(sessionEngine.focusedMode ? "Exit focused mode" : "Enter focused mode")
            }

            Button {
                togglePauseResume()
            } label: {
                Image(systemName: pauseResumeIcon)
                    .font(size.iconFont)
            }
            .buttonStyle(.plain)
            .help(pauseResumeHelp)

            Button {
                finishSession()
            } label: {
                Image(systemName: "checkmark")
                    .font(size.iconFont)
            }
            .buttonStyle(.plain)
            .help("Finish session")
        }
    }

    private func exitFocusIfNeeded() {
        guard sessionEngine.focusedMode else { return }
        onExitFocusMode?()
        sessionEngine.exitFocusedMode()
    }

    private func presentAfterFocusExit(_ action: @escaping () -> Void) {
        let wasFocused = sessionEngine.focusedMode
        exitFocusIfNeeded()
        if wasFocused {
            DispatchQueue.main.async(execute: action)
        } else {
            action()
        }
    }

    private func finishSession() {
        if sessionEngine.displayStudySeconds < 60 {
            presentAfterFocusExit { showShortSessionConfirm = true }
        } else {
            presentAfterFocusExit {
                sessionEngine.pauseForEnd()
                showEndSheet = true
            }
        }
    }

    private func togglePauseResume() {
        switch sessionEngine.state {
        case .studying:
            sessionEngine.pause()
        case .paused:
            sessionEngine.resume()
        case .idle:
            break
        }
    }

    private var pauseResumeIcon: String {
        switch sessionEngine.state {
        case .studying: "pause.fill"
        case .paused: "play.fill"
        case .idle: "pause.fill"
        }
    }

    private var pauseResumeHelp: String {
        switch sessionEngine.state {
        case .studying: "Pause"
        case .paused: "Resume"
        case .idle: "Pause"
        }
    }
}

struct ActiveSessionPill: View {
    @Environment(SessionEngine.self) private var sessionEngine
    @Environment(TermContext.self) private var termContext

    @Binding var showStartSheet: Bool
    @Binding var showEndSheet: Bool
    @Binding var showShortSessionConfirm: Bool

    var body: some View {
        if sessionEngine.isActive {
            activePill
        } else {
            startButton
        }
    }

    private var startButton: some View {
        Button {
            showStartSheet = true
        } label: {
            Text("Start Session")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!termContext.canStartLiveSession)
        .help(termContext.canStartLiveSession ? "Start a session" : "Switch to the active term to start a session")
        .popover(isPresented: $showStartSheet, arrowEdge: .top) {
            StartSessionSheet(isPresented: $showStartSheet)
        }
    }

    private var activePill: some View {
        let _ = sessionEngine.tickCount
        return HStack(spacing: 10) {
            Text(DurationFormatters.clock(seconds: sessionEngine.displayStudySeconds))
                .font(.body.monospacedDigit().weight(.semibold))

            SessionActiveControls(
                showEndSheet: $showEndSheet,
                showShortSessionConfirm: $showShortSessionConfirm,
                size: .compact
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: Capsule())
    }
}

struct FocusedSessionView: View {
    @Environment(SessionEngine.self) private var sessionEngine

    @Binding var showEndSheet: Bool
    @Binding var showShortSessionConfirm: Bool
    var onExitToDashboard: () -> Void

    var body: some View {
        let _ = sessionEngine.tickCount
        return VStack(spacing: 28) {
            if let course = sessionEngine.course {
                CoursePill(course: course, large: true)
            }

            Text(DurationFormatters.clock(seconds: sessionEngine.displayStudySeconds))
                .font(.system(size: 72, weight: .light, design: .rounded))
                .monospacedDigit()

            ActivitySwitcher(large: true)

            SessionActiveControls(
                showEndSheet: $showEndSheet,
                showShortSessionConfirm: $showShortSessionConfirm,
                size: .large,
                onExitFocusMode: onExitToDashboard
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
