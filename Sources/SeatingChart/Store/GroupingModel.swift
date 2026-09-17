import Foundation
import Observation

/// Which of the two "set either one" fields is live.
enum GroupSizingMode: String, CaseIterable, Identifiable {
    case groupCount
    case maxPerGroup

    var id: String { rawValue }
}

/// State behind the grouping tab and its floating overlay. Both views render
/// this same object, so a re-roll lands in the two of them at once.
///
/// The settings persist in `UserDefaults` — they are preferences, not document
/// content — while the drawn groups deliberately do not: a grouping is a live
/// draw, like the name picker's round. Export the PDF to keep one.
@Observable
final class GroupingModel {
    private enum Key {
        static let sizingMode = "grouping.sizingMode"
        static let groupCount = "grouping.groupCount"
        static let maxPerGroup = "grouping.maxPerGroup"
        static let quotaMale = "grouping.quotaMale"
        static let quotaFemale = "grouping.quotaFemale"
        static let pickRepresentatives = "grouping.pickRepresentatives"
        static let teamNames = "grouping.teamNames"
    }

    static let maxGroups = 30
    static let maxQuota = 12

    /// Deliberately separate from `AppStore.chartClassID`, for the same reason
    /// the name picker keeps its own: grouping one class should never disturb
    /// which class the seating chart is showing.
    var classID: UUID? {
        get {
            access(keyPath: \.classID)
            return storedClassID
        }
        set {
            guard newValue != storedClassID else { return }
            withMutation(keyPath: \.classID) { storedClassID = newValue }
            // A different class means a different draw.
            reset()
        }
    }

    var sizingMode: GroupSizingMode {
        get {
            access(keyPath: \.sizingMode)
            return storedSizingMode
        }
        set {
            withMutation(keyPath: \.sizingMode) {
                storedSizingMode = newValue
                defaults.set(newValue.rawValue, forKey: Key.sizingMode)
            }
        }
    }

    var groupCount: Int {
        get {
            access(keyPath: \.groupCount)
            return storedGroupCount
        }
        set {
            withMutation(keyPath: \.groupCount) {
                storedGroupCount = Self.clamp(newValue, 1, Self.maxGroups)
                defaults.set(storedGroupCount, forKey: Key.groupCount)
            }
        }
    }

    var maxPerGroup: Int {
        get {
            access(keyPath: \.maxPerGroup)
            return storedMaxPerGroup
        }
        set {
            withMutation(keyPath: \.maxPerGroup) {
                storedMaxPerGroup = Self.clamp(newValue, 1, Self.maxGroups)
                defaults.set(storedMaxPerGroup, forKey: Key.maxPerGroup)
            }
        }
    }

    var quotaMale: Int {
        get {
            access(keyPath: \.quotaMale)
            return storedQuotaMale
        }
        set {
            withMutation(keyPath: \.quotaMale) {
                storedQuotaMale = Self.clamp(newValue, 0, Self.maxQuota)
                defaults.set(storedQuotaMale, forKey: Key.quotaMale)
            }
        }
    }

    var quotaFemale: Int {
        get {
            access(keyPath: \.quotaFemale)
            return storedQuotaFemale
        }
        set {
            withMutation(keyPath: \.quotaFemale) {
                storedQuotaFemale = Self.clamp(newValue, 0, Self.maxQuota)
                defaults.set(storedQuotaFemale, forKey: Key.quotaFemale)
            }
        }
    }

    var pickRepresentatives: Bool {
        get {
            access(keyPath: \.pickRepresentatives)
            return storedPickRepresentatives
        }
        set {
            withMutation(keyPath: \.pickRepresentatives) {
                storedPickRepresentatives = newValue
                defaults.set(newValue, forKey: Key.pickRepresentatives)
            }
        }
    }

    /// Custom team names in order. Empty — or short — falls back to "Group 1…n".
    var teamNames: [String] {
        get {
            access(keyPath: \.teamNames)
            return storedTeamNames
        }
        set {
            withMutation(keyPath: \.teamNames) {
                storedTeamNames = newValue
                defaults.set(newValue, forKey: Key.teamNames)
            }
        }
    }

    /// The last draw. Session-only.
    private(set) var groups: [StudentGroup] = []
    /// Quota seats the last draw could not fill, for the hint line.
    private(set) var missingMale = 0
    private(set) var missingFemale = 0
    /// Mirrors the panel so the toolbar button knows which label to show.
    var isOverlayVisible = false

    @ObservationIgnored private var storedClassID: UUID?
    @ObservationIgnored private var storedSizingMode: GroupSizingMode
    @ObservationIgnored private var storedGroupCount: Int
    @ObservationIgnored private var storedMaxPerGroup: Int
    @ObservationIgnored private var storedQuotaMale: Int
    @ObservationIgnored private var storedQuotaFemale: Int
    @ObservationIgnored private var storedPickRepresentatives: Bool
    @ObservationIgnored private var storedTeamNames: [String]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedSizingMode = (defaults.string(forKey: Key.sizingMode))
            .flatMap(GroupSizingMode.init(rawValue:)) ?? .groupCount
        storedGroupCount = Self.clamp(defaults.object(forKey: Key.groupCount) as? Int ?? 2,
                                      1, Self.maxGroups)
        storedMaxPerGroup = Self.clamp(defaults.object(forKey: Key.maxPerGroup) as? Int ?? 4,
                                       1, Self.maxGroups)
        storedQuotaMale = Self.clamp(defaults.object(forKey: Key.quotaMale) as? Int ?? 0,
                                     0, Self.maxQuota)
        storedQuotaFemale = Self.clamp(defaults.object(forKey: Key.quotaFemale) as? Int ?? 0,
                                       0, Self.maxQuota)
        storedPickRepresentatives = defaults.object(forKey: Key.pickRepresentatives) as? Bool ?? false
        storedTeamNames = defaults.stringArray(forKey: Key.teamNames) ?? []
    }

    private static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(upper, max(lower, value))
    }

    // MARK: - Derived state

    var sizing: GroupSizing {
        switch sizingMode {
        case .groupCount: .groupCount(groupCount)
        case .maxPerGroup: .maxPerGroup(maxPerGroup)
        }
    }

    var quota: GroupQuota { GroupQuota(male: quotaMale, female: quotaFemale) }

    /// How many groups the current settings would make of this class.
    func plannedGroupCount(for students: [Student]) -> Int {
        GroupDraw.groupCount(for: sizing, studentCount: students.count)
    }

    // MARK: - Drawing

    func reset() {
        groups = []
        missingMale = 0
        missingFemale = 0
    }

    func make(from students: [Student]) {
        guard !students.isEmpty else {
            reset()
            return
        }
        let result = GroupDraw.make(from: students, sizing: sizing, quota: quota,
                                    teamNames: teamNames,
                                    pickRepresentatives: pickRepresentatives)
        groups = result.groups
        missingMale = result.missingMale
        missingFemale = result.missingFemale
    }

    /// Re-applies the current names to the groups already on screen, so editing
    /// the list in the sheet does not force a re-roll.
    func renameGroups() {
        for index in groups.indices {
            groups[index].name = GroupDraw.teamName(at: index, from: teamNames)
        }
    }
}
