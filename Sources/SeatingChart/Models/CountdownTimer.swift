import Foundation

/// The four one-click durations offered in the timer tab.
enum TimerPreset: Int, CaseIterable, Identifiable {
    case one = 60
    case three = 180
    case five = 300
    case ten = 600

    var id: Int { rawValue }
    var duration: TimeInterval { TimeInterval(rawValue) }
    var minutes: Int { rawValue / 60 }
}

/// A macOS system sound, referenced by name so nothing has to be bundled.
/// Deliberately AppKit-free: playing one is `TimerSound`'s job.
enum FinishSound: String, CaseIterable, Identifiable {
    case glass
    case ping
    case submarine
    case hero
    case funk

    var id: String { rawValue }

    /// The file name under `/System/Library/Sounds`, which is what `NSSound`
    /// looks up.
    var systemName: String {
        switch self {
        case .glass: "Glass"
        case .ping: "Ping"
        case .submarine: "Submarine"
        case .hero: "Hero"
        case .funk: "Funk"
        }
    }
}

/// Formatting and parsing a duration. Pure functions so the fiddly part — what
/// counts as a valid typed time — is testable without any UI.
enum Countdown {
    static let minDuration: TimeInterval = 1
    static let maxDuration: TimeInterval = 6 * 3600

    /// `"4:59"`, `"12:00"`, `"1:05:00"` past the hour. Rounds *up*, so a timer
    /// sitting at exactly 5 minutes reads `5:00` rather than `4:59`.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// What the user may type into the custom field:
    /// - `"7"` or `"1.5"` — minutes
    /// - `"90s"` — seconds, `"7m"` / `"7min"` — minutes
    /// - `"2:30"` — m:ss, `"1:05:00"` — h:mm:ss
    ///
    /// Returns `nil` for anything unparseable; a valid but out-of-range value is
    /// clamped rather than rejected, so `"0"` becomes one second and a typo of
    /// `"9999"` becomes the six-hour ceiling.
    static func parse(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            return clamp(parseClockForm(trimmed))
        }

        var number = trimmed
        var unitIsSeconds = false
        // Longest suffix first, or `"minutes"` gets claimed by the `"s"` of
        // seconds and parsed as `"10 minute"`.
        for unit in unitSuffixes where number.hasSuffix(unit.suffix) {
            number.removeLast(unit.suffix.count)
            unitIsSeconds = unit.isSeconds
            break
        }
        number = number.trimmingCharacters(in: .whitespaces)
        guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
        return clamp(unitIsSeconds ? value : value * 60)
    }

    private static let unitSuffixes: [(suffix: String, isSeconds: Bool)] = [
        ("seconds", true), ("minutes", false),
        ("second", true), ("minute", false),
        ("secs", true), ("mins", false),
        ("sec", true), ("min", false),
        ("s", true), ("m", false),
    ]

    /// `m:ss` or `h:mm:ss`. Every component must be a whole number, and every
    /// component after the first must be under 60 — `"2:75"` is a typo, not 195s.
    private static func parseClockForm(_ text: String) -> TimeInterval? {
        let parts = text.components(separatedBy: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var seconds: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty, piece.allSatisfy(\.isNumber),
                  let value = Int(piece) else { return nil }
            guard index == 0 || value < 60 else { return nil }
            seconds = seconds * 60 + TimeInterval(value)
        }
        return seconds
    }

    private static func clamp(_ seconds: TimeInterval?) -> TimeInterval? {
        guard let seconds else { return nil }
        return min(maxDuration, max(minDuration, seconds.rounded()))
    }
}
