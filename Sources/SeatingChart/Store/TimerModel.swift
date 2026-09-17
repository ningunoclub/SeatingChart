import Foundation
import Observation

enum TimerPhase {
    case idle
    case running
    case paused
    case finished
}

/// State behind the timer tab and its floating overlay. Both views render this
/// same object, so the countdown stays in step across the two.
///
/// Named `TimerModel`, not `Timer`, so `Foundation.Timer` below still resolves.
@Observable
final class TimerModel {
    private enum Key {
        static let duration = "timer.duration"
        static let sound = "timer.sound"
        static let soundEnabled = "timer.soundEnabled"
        static let doneImage = "timer.doneImage"
    }

    /// How long a run lasts. Changing it starts over — a timer mid-run whose
    /// length changed underneath would be lying about what it is counting.
    var duration: TimeInterval {
        get {
            access(keyPath: \.duration)
            return storedDuration
        }
        set {
            let clamped = min(Countdown.maxDuration, max(Countdown.minDuration, newValue))
            withMutation(keyPath: \.duration) {
                storedDuration = clamped
                defaults.set(clamped, forKey: Key.duration)
            }
            reset()
        }
    }

    var sound: FinishSound {
        get {
            access(keyPath: \.sound)
            return storedSound
        }
        set {
            withMutation(keyPath: \.sound) {
                storedSound = newValue
                defaults.set(newValue.rawValue, forKey: Key.sound)
            }
        }
    }

    var soundEnabled: Bool {
        get {
            access(keyPath: \.soundEnabled)
            return storedSoundEnabled
        }
        set {
            withMutation(keyPath: \.soundEnabled) {
                storedSoundEnabled = newValue
                defaults.set(newValue, forKey: Key.soundEnabled)
            }
        }
    }

    /// File name inside the shared `Images/` folder; `nil` shows the symbol.
    var doneImageFileName: String? {
        get {
            access(keyPath: \.doneImageFileName)
            return storedDoneImage
        }
        set {
            withMutation(keyPath: \.doneImageFileName) {
                storedDoneImage = newValue
                if let newValue {
                    defaults.set(newValue, forKey: Key.doneImage)
                } else {
                    defaults.removeObject(forKey: Key.doneImage)
                }
            }
        }
    }

    private(set) var phase: TimerPhase = .idle
    /// Seconds left. Derived from `endDate` while running, never decremented.
    private(set) var remaining: TimeInterval
    /// Mirrors the panel so the toolbar button knows which label to show.
    var isOverlayVisible = false
    /// Text in the custom-duration field. Session-only: a preset is what gets
    /// remembered across launches, not what was half-typed.
    var customInput = ""

    @ObservationIgnored private var storedDuration: TimeInterval
    @ObservationIgnored private var storedSound: FinishSound
    @ObservationIgnored private var storedSoundEnabled: Bool
    @ObservationIgnored private var storedDoneImage: String?
    /// When the current run is due to end. `nil` unless running.
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Key.duration) as? Double
        storedDuration = saved.map {
            min(Countdown.maxDuration, max(Countdown.minDuration, $0))
        } ?? TimerPreset.five.duration
        storedSound = (defaults.string(forKey: Key.sound))
            .flatMap(FinishSound.init(rawValue:)) ?? .glass
        storedSoundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        storedDoneImage = defaults.string(forKey: Key.doneImage)
        remaining = storedDuration
    }

    deinit { ticker?.invalidate() }

    // MARK: - Derived state

    /// The preset matching the current duration, or `nil` for a custom time —
    /// which is what leaves the segmented picker showing no selection.
    var selectedPreset: TimerPreset? {
        TimerPreset.allCases.first { $0.duration == duration }
    }

    /// 0 at the start of a run, 1 when it finishes.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    var isRunning: Bool { phase == .running }

    // MARK: - Transport

    func toggle() {
        switch phase {
        case .running: pause()
        case .idle, .paused: start()
        case .finished:
            reset()
            start()
        }
    }

    func start() {
        guard phase != .running else { return }
        if remaining <= 0 { remaining = duration }
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running, let endDate else { return }
        stopTicker()
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        phase = .paused
    }

    func reset() {
        stopTicker()
        endDate = nil
        remaining = duration
        phase = .idle
    }

    func select(_ preset: TimerPreset) {
        duration = preset.duration
        customInput = ""
    }

    /// Applies whatever is in the custom field. Leaves the field alone when it
    /// cannot be read, so the user can see and fix their typo.
    @discardableResult
    func applyCustomInput() -> Bool {
        guard let parsed = Countdown.parse(customInput) else { return false }
        duration = parsed
        customInput = Countdown.format(parsed)
        return true
    }

    func previewSound() {
        TimerSound.play(sound)
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        // 10 Hz: fine-grained enough for the progress bar, cheap enough to
        // ignore. `.common` mode, or the countdown freezes while the overlay is
        // being dragged or a menu is held open.
        let next = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(next, forMode: .common)
        ticker = next
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Recomputed from `endDate` rather than decremented, so the countdown never
    /// drifts — and a Mac that slept past the end wakes straight into `.finished`.
    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            finish()
        } else {
            remaining = left
        }
    }

    private func finish() {
        stopTicker()
        endDate = nil
        remaining = 0
        phase = .finished
        if soundEnabled { TimerSound.play(sound) }
    }
}
