import SwiftUI
import SwiftData
import Charts

struct StudyTimeBar: Identifiable {
    let id: String
    let name: String
    let seconds: Int
    let color: Color
}

struct StudyTimeBarChart: View {
    let bars: [StudyTimeBar]
    var footnote: String?
    /// Minimum x-axis maximum (seconds); chart spans at least this much when set.
    var minXScaleSeconds: Int?

    @State private var hoveredName: String?
    @State private var revealedName: String?
    @State private var revealTask: Task<Void, Never>?

    private let hoverRevealDelay: Duration = .milliseconds(500)
    private let hitAreaBandRatio: CGFloat = 1.0

    private var sortedBars: [StudyTimeBar] {
        bars.sorted { $0.seconds > $1.seconds }
    }

    private var xScaleMax: Int {
        let dataMax = bars.map(\.seconds).max() ?? 0
        if let minXScaleSeconds {
            return max(dataMax, minXScaleSeconds)
        }
        return dataMax
    }

    private var xScaleDomainMax: Int {
        max(xScaleMax, 1)
    }

    private var xAxisMarkValues: [Int] {
        let maxVal = xScaleDomainMax
        return (0...4).map { $0 * maxVal / 4 }
    }

    private let xPlotPadding: CGFloat = 8

    private var idealChartHeight: CGFloat {
        min(140, max(56, CGFloat(sortedBars.count) * 28 + 8))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                barChart(height: fittedHeight(in: geo.size.height))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear {
            revealTask?.cancel()
        }
    }

    private func fittedHeight(in available: CGFloat) -> CGFloat {
        guard available > 1 else { return idealChartHeight }
        return min(idealChartHeight, available)
    }

    /// Bar thickness that stays inside each category band, so many activities keep a gap instead of stacking.
    private func barThickness(chartHeight: CGFloat) -> CGFloat {
        let count = CGFloat(max(sortedBars.count, 1))
        let plot = max(24, chartHeight - 28)
        let band = plot / count
        let gap: CGFloat = count <= 3 ? 8 : 4
        return min(16, max(3, band - gap))
    }

    private func barChart(height: CGFloat) -> some View {
        let thickness = barThickness(chartHeight: height)
        return Chart(sortedBars) { bar in
            BarMark(
                x: .value("Time", bar.seconds),
                y: .value("Name", bar.name),
                height: .fixed(thickness)
            )
            .foregroundStyle(bar.color)
            .cornerRadius(thickness / 2)
            .opacity(hoveredName == nil || hoveredName == bar.name ? 1 : 0.35)
        }
        .chartXScale(
            domain: 0...xScaleDomainMax,
            range: .plotDimension(padding: xPlotPadding)
        )
        .chartXAxis {
            AxisMarks(values: xAxisMarkValues) { value in
                AxisGridLine()
                AxisValueLabel(centered: true) {
                    if let seconds = value.as(Int.self) {
                        Text(DurationFormatters.compactHours(seconds))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHover(selectedBarName(at: location, proxy: proxy, geometry: geometry))
                            case .ended:
                                updateHover(nil)
                            }
                        }

                    if let revealedName,
                       let bar = bars.first(where: { $0.name == revealedName }) {
                        inBarLabel(for: bar, proxy: proxy, geometry: geometry)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: revealedName)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredName)
        .frame(height: height)
    }

    @ViewBuilder
    private func inBarLabel(for bar: StudyTimeBar, proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame,
           let yRange = proxy.positionRange(forY: bar.name),
           let xEnd = proxy.position(forX: bar.seconds),
           let xStart = proxy.position(forX: 0) {
            let plotRect = geometry[plotFrame]
            let barWidth = max(0, xEnd - xStart)
            let bandHeight = yRange.upperBound - yRange.lowerBound
            Text("\(bar.name) (\(DurationFormatters.compactHours(bar.seconds)))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.leading, 8)
                .frame(width: barWidth, height: bandHeight, alignment: .leading)
                .clipped()
                .offset(x: plotRect.minX + xStart, y: plotRect.minY + yRange.lowerBound)
        }
    }

    private func updateHover(_ name: String?) {
        if name == hoveredName { return }
        revealTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            hoveredName = name
            revealedName = nil
        }
        guard let name else { return }
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: hoverRevealDelay)
            guard !Task.isCancelled, hoveredName == name else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                revealedName = name
            }
        }
    }

    private func selectedBarName(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else { return nil }

        let plotY = location.y - plotRect.minY
        guard let name = proxy.value(atY: plotY, as: String.self),
              let yRange = proxy.positionRange(forY: name) else { return nil }

        let bandHeight = yRange.upperBound - yRange.lowerBound
        let inset = bandHeight * (1 - hitAreaBandRatio) / 2
        guard plotY >= yRange.lowerBound + inset, plotY <= yRange.upperBound - inset else { return nil }
        return name
    }
}

enum DashboardLayout {
    static let gridSpacing: CGFloat = 16
    static let overviewRowHeight: CGFloat = 182
    static let chartRowHeight: CGFloat = 184
    static let wideRowHeight: CGFloat = 196
}

struct HeatmapView: View {
    let dailyTotals: [DailyStudyTotal]
    let trackingStart: Date
    let termFirstDay: Date
    let termLastDay: Date
    let fullColorSeconds: Int
    let themeColor: Color
    var visibleStart: Date? = nil
    var visibleEnd: Date? = nil
    /// When true, the grid is cropped to `visibleStart`...`visibleEnd` instead of a 12-month window.
    var cropToVisibleRange: Bool = false

    @State private var hoveredDay: Date?
    /// Distance scrolled into older weeks. 0 keeps the current week on the trailing edge.
    @State private var fromTrailing: CGFloat = 0

    private let spacing: CGFloat = 3
    private let captionHeight: CGFloat = 16
    private let gridHeight: CGFloat = 101

    var body: some View {
        let layout = HeatmapLayout(
            dailyTotals: dailyTotals,
            trackingStart: trackingStart,
            termFirstDay: termFirstDay,
            termLastDay: termLastDay,
            fullColorSeconds: fullColorSeconds,
            themeColor: themeColor,
            spacing: spacing,
            gridHeight: gridHeight,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            cropToVisibleRange: cropToVisibleRange
        )

        VStack(alignment: .leading, spacing: 6) {
            // Trailing-relative positioning (not ScrollView): when the card shrinks,
            // offset stays tied to the trailing edge so the current week never jumps.
            GeometryReader { geo in
                let maxScroll = max(0, layout.contentWidth - geo.size.width)
                let travel = min(max(fromTrailing, 0), maxScroll)
                let originX = geo.size.width - layout.contentWidth + travel

                ZStack(alignment: .topLeading) {
                    heatmapCanvas(layout: layout)
                        .frame(width: layout.contentWidth, height: gridHeight)
                        .offset(x: originX)

                    HeatmapScrollMonitor(maxScroll: maxScroll, fromTrailing: $fromTrailing)
                }
                .frame(width: geo.size.width, height: gridHeight, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let canvasPoint = CGPoint(x: location.x - originX, y: location.y)
                        hoveredDay = layout.day(at: canvasPoint)
                    case .ended:
                        hoveredDay = nil
                    }
                }
                .help(hoveredDay.map { layout.tooltip(for: $0) } ?? "")
            }
            .frame(height: gridHeight)

            Text(hoveredDay.map { layout.tooltip(for: $0) } ?? " ")
                .font(.caption)
                .foregroundStyle(hoveredDay == nil ? .clear : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: captionHeight, maxHeight: captionHeight, alignment: .leading)
        }
    }

    private func heatmapCanvas(layout: HeatmapLayout) -> some View {
        Canvas { context, _ in
            for (weekIndex, week) in layout.weeks.enumerated() {
                for (dayIndex, day) in week.enumerated() {
                    let rect = layout.rect(weekIndex: weekIndex, dayIndex: dayIndex)
                    let path = RoundedRectangle(cornerRadius: 2, style: .continuous).path(in: rect)
                    context.fill(path, with: .color(layout.cellColor(for: day)))
                }
            }

            if let hoveredDay,
               let rect = layout.rect(for: hoveredDay) {
                let path = RoundedRectangle(cornerRadius: 2, style: .continuous).path(in: rect)
                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.45)),
                    lineWidth: 1
                )
            }
        }
    }
}

/// Captures trackpad/mouse-wheel scrolls over the heatmap without stealing hover hits.
private struct HeatmapScrollMonitor: NSViewRepresentable {
    var maxScroll: CGFloat
    @Binding var fromTrailing: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(fromTrailing: $fromTrailing)
    }

    func makeNSView(context: Context) -> HeatmapScrollMonitorView {
        let view = HeatmapScrollMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HeatmapScrollMonitorView, context: Context) {
        context.coordinator.maxScroll = maxScroll
        context.coordinator.fromTrailing = $fromTrailing
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var maxScroll: CGFloat = 0
        var fromTrailing: Binding<CGFloat>

        init(fromTrailing: Binding<CGFloat>) {
            self.fromTrailing = fromTrailing
        }

        func applyScroll(delta: CGFloat) {
            guard maxScroll > 0, delta != 0 else { return }
            // Positive delta moves content right → reveals older weeks on the left.
            let next = fromTrailing.wrappedValue + delta
            fromTrailing.wrappedValue = min(max(next, 0), maxScroll)
        }
    }
}

private final class HeatmapScrollMonitorView: NSView {
    weak var coordinator: HeatmapScrollMonitor.Coordinator?
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.containsCursor(for: event) else { return event }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX
                : event.scrollingDeltaY
            self.coordinator?.applyScroll(delta: delta)
            return nil
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    deinit {
        removeMonitor()
    }

    /// Let SwiftUI keep hover/hit testing; we only listen via the event monitor.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func containsCursor(for event: NSEvent) -> Bool {
        guard let window else { return false }
        let pointInWindow = event.locationInWindow
        let pointInView = convert(pointInWindow, from: nil)
        return bounds.contains(pointInView) && window === event.window
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct HeatmapLayout {
    let weeks: [[Date]]
    let cellSize: CGFloat
    let spacing: CGFloat
    let gridHeight: CGFloat
    let secondsByDay: [Date: Int]
    let termFirstDayStart: Date
    let termLastDayStart: Date
    let trackingStart: Date
    let today: Date
    let fullColorSeconds: Int
    let themeColor: Color

    var contentWidth: CGFloat {
        let columns = CGFloat(weeks.count)
        return columns * cellSize + max(0, columns - 1) * spacing
    }

    init(
        dailyTotals: [DailyStudyTotal],
        trackingStart: Date,
        termFirstDay: Date,
        termLastDay: Date,
        fullColorSeconds: Int,
        themeColor: Color,
        spacing: CGFloat,
        gridHeight: CGFloat,
        visibleStart: Date?,
        visibleEnd: Date?,
        cropToVisibleRange: Bool
    ) {
        self.trackingStart = trackingStart
        self.termFirstDayStart = termFirstDay.startOfDay
        self.termLastDayStart = termLastDay.startOfDay
        self.fullColorSeconds = fullColorSeconds
        self.themeColor = themeColor
        self.spacing = spacing
        self.gridHeight = gridHeight
        self.today = Date().startOfDay
        self.secondsByDay = Dictionary(uniqueKeysWithValues: dailyTotals.map { ($0.date.startOfDay, $0.seconds) })
        self.cellSize = max(2, (gridHeight - 6 * spacing) / 7)

        let rangeEnd = min(today, termLastDayStart, visibleEnd?.startOfDay ?? today)
        let currentWeekStart = Self.startOfWeek(for: rangeEnd)
        let firstWeekStart: Date
        if cropToVisibleRange, let visibleStart {
            firstWeekStart = Self.startOfWeek(for: visibleStart)
        } else {
            let twelveMonthsAgo = Calendar.app.date(byAdding: .month, value: -12, to: currentWeekStart) ?? currentWeekStart
            firstWeekStart = Self.startOfWeek(for: twelveMonthsAgo)
        }

        var builtWeeks: [[Date]] = []
        var weekStart = firstWeekStart
        while weekStart <= currentWeekStart {
            var week: [Date] = []
            for offset in 0..<7 {
                if let day = Calendar.app.date(byAdding: .day, value: offset, to: weekStart) {
                    week.append(day)
                }
            }
            builtWeeks.append(week)
            guard let next = Calendar.app.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        self.weeks = builtWeeks
    }

    func rect(weekIndex: Int, dayIndex: Int) -> CGRect {
        let size = max(cellSize, 2)
        return CGRect(
            x: CGFloat(weekIndex) * (cellSize + spacing),
            y: CGFloat(dayIndex) * (cellSize + spacing),
            width: size,
            height: size
        )
    }

    func rect(for day: Date) -> CGRect? {
        let dayStart = day.startOfDay
        for (weekIndex, week) in weeks.enumerated() {
            if let dayIndex = week.firstIndex(where: { $0.startOfDay == dayStart }) {
                return rect(weekIndex: weekIndex, dayIndex: dayIndex)
            }
        }
        return nil
    }

    func day(at point: CGPoint) -> Date? {
        guard point.x >= 0, point.y >= 0, point.y < gridHeight else { return nil }

        let column = Int(point.x / (cellSize + spacing))
        guard column >= 0, column < weeks.count else { return nil }

        let columnOriginX = CGFloat(column) * (cellSize + spacing)
        guard point.x - columnOriginX <= cellSize else { return nil }

        let row = Int(point.y / (cellSize + spacing))
        guard row >= 0, row < 7 else { return nil }

        let rowOriginY = CGFloat(row) * (cellSize + spacing)
        guard point.y - rowOriginY <= cellSize else { return nil }

        return weeks[column][row]
    }

    func cellColor(for day: Date) -> Color {
        let dayStart = day.startOfDay
        let outOfTerm = dayStart < termFirstDayStart || dayStart > termLastDayStart
        let untracked = !outOfTerm && StudyTimeAttribution.isUntrackedDay(day, trackingStart: trackingStart)
        let future = !outOfTerm && dayStart > today
        let seconds = secondsByDay[dayStart] ?? 0

        if outOfTerm { return Color.secondary.opacity(0.04) }
        if untracked { return Color.secondary.opacity(0.14) }
        if future { return Color.secondary.opacity(0.06) }
        let t = min(1.0, Double(seconds) / Double(max(fullColorSeconds, 60)))
        return themeColor.opacity(0.12 + t * 0.88)
    }

    func tooltip(for day: Date) -> String {
        let dayStart = day.startOfDay
        let outOfTerm = dayStart < termFirstDayStart || dayStart > termLastDayStart
        let untracked = !outOfTerm && StudyTimeAttribution.isUntrackedDay(day, trackingStart: trackingStart)
        let future = !outOfTerm && dayStart > today
        let seconds = secondsByDay[dayStart] ?? 0
        let date = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        if outOfTerm { return "\(date): Outside term" }
        if untracked { return "\(date): Before tracking started" }
        if future { return "\(date): No study yet" }
        return "\(date): \(DurationFormatters.compactHours(seconds))"
    }

    private static func startOfWeek(for date: Date) -> Date {
        let weekday = Calendar.app.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        return Calendar.app.date(byAdding: .day, value: -daysFromMonday, to: date.startOfDay) ?? date.startOfDay
    }
}

struct ChartUnlockPlaceholder: View {
    let remainingDays: Int
    let chartName: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        let unit = remainingDays == 1 ? "day" : "days"
        return "Log \(remainingDays) more study \(unit) to see your \(chartName)."
    }
}

struct ChartOneDayPlaceholder: View {
    var body: some View {
        Text("That wouldn't make much sense!")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QualityTrendSample: Identifiable {
    let date: Date
    let average: Double
    var id: Date { date }
}

struct FocusTrendChart: View {
    let points: [FocusTrendPoint]
    let range: DashboardTimeRange
    let themeColor: Color

    @State private var selectedID: PersistentIdentifier?

    private let hoverAnimation = Animation.easeInOut(duration: 0.18)

    /// One sample per rated day: the mean of that day's ratings, then a trailing mean over the range window.
    private var trendSamples: [QualityTrendSample] {
        let grouped = Dictionary(grouping: points) { $0.date.startOfDay }
        let days = grouped.keys.sorted()
        let window = max(1, range.qualityTrendWindowDays)
        return days.map { day in
            let cutoff = Calendar.app.date(byAdding: .day, value: -(window - 1), to: day) ?? day
            let included = days.filter { $0 >= cutoff && $0 <= day }
            let means = included.map { includedDay -> Double in
                let ratings = grouped[includedDay] ?? []
                let total = ratings.reduce(0.0) { $0 + $1.rating }
                return total / Double(max(ratings.count, 1))
            }
            let average = means.reduce(0, +) / Double(max(means.count, 1))
            let anchor = grouped[day]?.map(\.date).max() ?? day
            return QualityTrendSample(date: anchor, average: average)
        }
    }

    var body: some View {
        if points.isEmpty {
            Text("No quality ratings yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Chart {
                ForEach(trendSamples) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Rating", sample.average),
                        series: .value("Series", "Trend")
                    )
                    .foregroundStyle(themeColor)
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...5)
            .chartYAxis {
                AxisMarks(values: [1, 2, 3, 4, 5])
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let selected = points.first { $0.id == selectedID }
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let next = nearestPoint(at: location, proxy: proxy, geometry: geometry)?.id
                                    guard next != selectedID else { return }
                                    withAnimation(hoverAnimation) {
                                        selectedID = next
                                    }
                                case .ended:
                                    guard selectedID != nil else { return }
                                    withAnimation(hoverAnimation) {
                                        selectedID = nil
                                    }
                                }
                            }

                        if let selected {
                            focusCaption(for: selected, proxy: proxy, geometry: geometry)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func focusCaption(for point: FocusTrendPoint, proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame,
           let x = proxy.position(forX: point.date),
           let y = proxy.position(forY: point.rating) {
            let plotRect = geometry[plotFrame]
            Text(sessionCaption(point))
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .fixedSize()
                .position(x: plotRect.minX + x, y: max(14, plotRect.minY + y - 22))
        }
    }

    private func sessionCaption(_ point: FocusTrendPoint) -> String {
        let when = point.date.formatted(date: .abbreviated, time: .shortened)
        let time = DurationFormatters.compactHours(point.studySeconds)
        if point.activityNames.isEmpty {
            return "\(point.courseName) · \(when) (\(time))"
        }
        return "\(point.courseName) · \(point.activityNames) · \(when) (\(time))"
    }

    private func nearestPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> FocusTrendPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else { return nil }

        var best: FocusTrendPoint?
        var bestDistance = CGFloat.infinity
        for point in points {
            guard let x = proxy.position(forX: point.date),
                  let y = proxy.position(forY: point.rating)
            else { continue }
            let dx = location.x - (plotRect.minX + x)
            let dy = location.y - (plotRect.minY + y)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = point
            }
        }
        return bestDistance <= 24 * 24 ? best : nil
    }
}

struct RadarChartView: View {
    let weekdayAverages: [Int]
    let themeColor: Color
    private let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 24
            let maxVal = max(weekdayAverages.max() ?? 1, 3600)

            ZStack {
                Canvas { context, size in
                    let chartCenter = CGPoint(x: size.width / 2, y: size.height / 2)
                    let chartRadius = min(size.width, size.height) / 2 - 24

                    for level in 1...4 {
                        let r = chartRadius * CGFloat(level) / 4
                        var path = Path()
                        for i in 0..<7 {
                            let angle = angleFor(index: i)
                            let point = CGPoint(x: chartCenter.x + cos(angle) * r, y: chartCenter.y + sin(angle) * r)
                            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                    }

                    var dataPath = Path()
                    for i in 0..<7 {
                        let val = CGFloat(weekdayAverages[i]) / CGFloat(maxVal)
                        let angle = angleFor(index: i)
                        let point = CGPoint(
                            x: chartCenter.x + cos(angle) * chartRadius * val,
                            y: chartCenter.y + sin(angle) * chartRadius * val
                        )
                        if i == 0 { dataPath.move(to: point) } else { dataPath.addLine(to: point) }
                    }
                    dataPath.closeSubpath()
                    context.fill(dataPath, with: .color(themeColor.opacity(0.35)))
                    context.stroke(dataPath, with: .color(themeColor), lineWidth: 2)
                }

                ForEach(labels.indices, id: \.self) { index in
                    let angle = angleFor(index: index)
                    let labelRadius = radius + 14
                    let x = center.x + cos(angle) * labelRadius
                    let y = center.y + sin(angle) * labelRadius
                    Text(labels[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: x, y: y)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func angleFor(index: Int) -> CGFloat {
        let fraction = CGFloat(index) / 7.0
        return fraction * 2 * .pi - .pi / 2
    }
}
