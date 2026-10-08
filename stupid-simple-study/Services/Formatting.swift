import SwiftUI

enum CourseColorPalette {
    static let hexColors: [String] = [
        "#7C5CFC", "#3B82F6", "#10B981", "#F59E0B", "#EF4444",
    ]

    static func nextColor(usedHexes: Set<String>) -> String {
        for hex in hexColors where !usedHexes.contains(hex.uppercased()) {
            return hex
        }
        return hexColors.randomElement() ?? "#7C5CFC"
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func hexString() -> String {
        #if canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "#7C5CFC" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#7C5CFC"
        #endif
    }
}

struct DurationFormatters {
    static func clock(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func menuBarClock(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func compactHours(_ seconds: Int, style: DurationDisplayStyle) -> String {
        switch style {
        case .hoursAndMinutes:
            let totalMinutes = max(0, Int((Double(seconds) / 60).rounded()))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours == 0 { return "\(minutes)m" }
            if minutes == 0 { return "\(hours)h" }
            return "\(hours)h \(minutes)m"
        case .decimalHours:
            return decimalHours(seconds)
        }
    }

    private static func decimalHours(_ seconds: Int) -> String {
        let hours = Double(seconds) / 3600.0
        if hours < 1 {
            return String(format: "%.0fm", Double(seconds) / 60.0)
        }
        if hours < 10 {
            let tenths = (hours * 10).rounded() / 10
            if tenths == tenths.rounded() {
                return "\(Int(tenths))h"
            }
            return String(format: "%.1fh", tenths)
        }
        return String(format: "%.0fh", hours)
    }

    static func sessionListDate(_ date: Date) -> String {
        if Calendar.app.isDateInToday(date) {
            return "Today"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Calendar {
    static let app = Calendar.current

    func days(from start: Date, through end: Date) -> [Date] {
        var days: [Date] = []
        var current = startOfDay(for: start)
        let last = startOfDay(for: end)
        while current <= last {
            days.append(current)
            guard let next = date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }
}

extension Date {
    var startOfDay: Date { Calendar.app.startOfDay(for: self) }

    func isSameDay(as other: Date) -> Bool {
        Calendar.app.isDate(self, inSameDayAs: other)
    }
}
