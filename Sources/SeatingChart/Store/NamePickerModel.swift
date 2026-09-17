import Foundation
import Observation

/// State behind the name picker tab and the floating overlay. Both views render
/// this same object, so the shuffle animation stays in step across the two.
@Observable
final class NamePickerModel {
    private enum Key {
        static let displayMode = "namePicker.displayMode"
        static let avoidRepeats = "namePicker.avoidRepeats"
    }

    /// Deliberately separate from `AppStore.chartClassID`: picking names should
    /// never disturb which class the seating chart is showing.
    var classID: UUID? {
        get {
            access(keyPath: \.classID)
            return storedClassID
        }
        set {
            guard newValue != storedClassID else { return }
            withMutation(keyPath: \.classID) { storedClassID = newValue }
            // A different class means a different round.
            reset()
        }
    }

    var displayMode: PickerDisplayMode {
        get {
            access(keyPath: \.displayMode)
            return storedDisplayMode
        }
        set {
            withMutation(keyPath: \.displayMode) {
                storedDisplayMode = newValue
                defaults.set(newValue.rawValue, forKey: Key.displayMode)
            }
        }
    }

    var avoidRepeats: Bool {
        get {
            access(keyPath: \.avoidRepeats)
            return storedAvoidRepeats
        }
        set {
            withMutation(keyPath: \.avoidRepeats) {
                storedAvoidRepeats = newValue
                defaults.set(newValue, forKey: Key.avoidRepeats)
            }
        }
    }

    /// Who has had a turn this round, in pick order.
    private(set) var pickedIDs: [UUID] = []
    /// What both views draw right now — during a shuffle this flickers.
    private(set) var displayedStudentID: UUID?
    private(set) var isShuffling = false
    /// Mirrors the panel so the toolbar button knows which label to show.
    var isOverlayVisible = false

    @ObservationIgnored private var storedClassID: UUID?
    @ObservationIgnored private var storedDisplayMode: PickerDisplayMode
    @ObservationIgnored private var storedAvoidRepeats: Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedDisplayMode = (defaults.string(forKey: Key.displayMode))
            .flatMap(PickerDisplayMode.init(rawValue:)) ?? .both
        storedAvoidRepeats = defaults.object(forKey: Key.avoidRepeats) as? Bool ?? true
    }

    deinit { timer?.invalidate() }

    // MARK: - Round bookkeeping

    func pickedCount(in students: [Student]) -> Int {
        NameDraw.pickedCount(in: students, picked: pickedIDs)
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isShuffling = false
        pickedIDs = []
        displayedStudentID = nil
    }

    // MARK: - Drawing

    /// Slot-machine settle: fast flicker at first, slowing into the reveal.
    private static let shuffleSteps: [TimeInterval] = {
        var steps: [TimeInterval] = []
        var interval: TimeInterval = 0.055
        var elapsed: TimeInterval = 0
        while elapsed < 0.8 {
            steps.append(interval)
            elapsed += interval
            interval = min(0.18, interval * 1.18)
        }
        return steps
    }()

    func pick(from students: [Student]) {
        timer?.invalidate()
        timer = nil
        guard let result = NameDraw.next(from: students, picked: pickedIDs,
                                         avoidRepeats: avoidRepeats) else { return }
        // Nothing to shuffle through when there is only one name.
        guard students.count > 1 else {
            commit(result)
            return
        }
        isShuffling = true
        runShuffle(step: 0, students: students, result: result)
    }

    private func runShuffle(step: Int, students: [Student],
                            result: (winner: UUID, picked: [UUID])) {
        guard step < Self.shuffleSteps.count else {
            isShuffling = false
            commit(result)
            return
        }
        // Never flash the winner mid-run — the reveal should land, not repeat.
        displayedStudentID = students.filter { $0.id != result.winner }
            .randomElement()?.id ?? result.winner

        // `.common` mode, or the flicker stalls while the overlay is being
        // dragged or a menu is held open.
        let next = Timer(timeInterval: Self.shuffleSteps[step], repeats: false) { [weak self] _ in
            self?.runShuffle(step: step + 1, students: students, result: result)
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func commit(_ result: (winner: UUID, picked: [UUID])) {
        timer = nil
        isShuffling = false
        displayedStudentID = result.winner
        pickedIDs = result.picked
    }
}
