import Foundation

/// How the class is cut up. The two cases are the "set either one" pair from the
/// settings bar — only ever one of them is live.
enum GroupSizing: Hashable {
    case groupCount(Int)
    case maxPerGroup(Int)
}

/// How many of each gender every group must get. `0 / 0` means "no quota" — the
/// genders are then simply spread as evenly as the class allows.
struct GroupQuota: Hashable {
    var male: Int
    var female: Int

    static let none = GroupQuota(male: 0, female: 0)

    var isActive: Bool { male > 0 || female > 0 }
}

struct StudentGroup: Identifiable, Hashable {
    var id: UUID
    var name: String
    var memberIDs: [UUID]
    /// One member drawn to speak for the group; `nil` when the option is off.
    var representativeID: UUID?

    init(id: UUID = UUID(), name: String, memberIDs: [UUID],
         representativeID: UUID? = nil) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.representativeID = representativeID
    }
}

struct GroupingResult: Hashable {
    var groups: [StudentGroup]
    /// Quota seats that could not be filled, because the class ran out of
    /// students of that gender. Not an error — the draw fills what it can.
    var missingMale: Int
    var missingFemale: Int

    static let empty = GroupingResult(groups: [], missingMale: 0, missingFemale: 0)

    var isShort: Bool { missingMale > 0 || missingFemale > 0 }
}

/// Splitting a class into teams. Pure functions, so the interesting part — even
/// sizes and an even gender spread — is testable without any UI, the way
/// `NameDraw` and `SeatingGenerator` are.
enum GroupDraw {
    /// Shared by the steppers and the draw, so the preview count in the settings
    /// bar can never disagree with what generating actually produces.
    static func groupCount(for sizing: GroupSizing, studentCount: Int) -> Int {
        guard studentCount > 0 else { return 0 }
        switch sizing {
        case let .groupCount(requested):
            return max(1, min(requested, studentCount))
        case let .maxPerGroup(perGroup):
            let size = max(1, perGroup)
            // Ceiling division: the last group takes the remainder.
            return (studentCount + size - 1) / size
        }
    }

    static func tally(_ students: [Student]) -> (male: Int, female: Int, unspecified: Int) {
        (students.count { $0.gender == .male },
         students.count { $0.gender == .female },
         students.count { $0.gender == .unspecified })
    }

    /// The custom name for a group, or the numbered fallback. Blank entries in
    /// the list count as "not set" rather than producing a nameless card.
    static func teamName(at index: Int, from names: [String]) -> String {
        if index < names.count {
            let trimmed = names[index].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return L("grouping.default_team", index + 1)
    }

    static func make(from students: [Student], sizing: GroupSizing,
                     quota: GroupQuota = .none, teamNames: [String] = [],
                     pickRepresentatives: Bool = false) -> GroupingResult {
        var rng = SystemRandomNumberGenerator()
        return make(from: students, sizing: sizing, quota: quota, teamNames: teamNames,
                    pickRepresentatives: pickRepresentatives, using: &rng)
    }

    static func make<G: RandomNumberGenerator>(
        from students: [Student],
        sizing: GroupSizing,
        quota: GroupQuota = .none,
        teamNames: [String] = [],
        pickRepresentatives: Bool = false,
        using rng: inout G
    ) -> GroupingResult {
        let count = groupCount(for: sizing, studentCount: students.count)
        guard count > 0 else { return .empty }

        // One shuffled pool per gender. Dealing pool by pool is what makes the
        // genders come out even without any balancing pass afterwards.
        var pools: [Gender: [UUID]] = [:]
        for gender in Gender.allCases {
            pools[gender] = students.filter { $0.gender == gender }
                .map(\.id)
                .shuffled(using: &rng)
        }

        var buckets: [[UUID]] = Array(repeating: [], count: count)
        var result = GroupingResult(groups: [], missingMale: 0, missingFemale: 0)

        if quota.isActive {
            result.missingMale = deal(quota.male, from: &pools[.male]!, into: &buckets)
            result.missingFemale = deal(quota.female, from: &pools[.female]!, into: &buckets)
        }

        // Whatever the quota did not claim goes to the smallest group each time,
        // which keeps the sizes within one of each other.
        for gender in [Gender.male, .female, .unspecified] {
            while let next = pools[gender]?.popLast() {
                buckets[smallestIndex(in: buckets, using: &rng)].append(next)
            }
        }

        result.groups = buckets.enumerated().map { index, members in
            // Dealt gender by gender, so the raw order would list all the boys
            // first — shuffle before anyone reads it off a card.
            let shuffled = members.shuffled(using: &rng)
            return StudentGroup(
                name: teamName(at: index, from: teamNames),
                memberIDs: shuffled,
                representativeID: pickRepresentatives ? shuffled.randomElement(using: &rng) : nil
            )
        }
        return result
    }

    // MARK: - Dealing

    /// Puts `perGroup` students into every bucket. Returns how many seats went
    /// unfilled because the pool ran dry.
    private static func deal(_ perGroup: Int, from pool: inout [UUID],
                             into buckets: inout [[UUID]]) -> Int {
        guard perGroup > 0 else { return 0 }
        var missing = 0
        for index in buckets.indices {
            for _ in 0..<perGroup {
                if let next = pool.popLast() {
                    buckets[index].append(next)
                } else {
                    missing += 1
                }
            }
        }
        return missing
    }

    /// Ties are broken at random, so group 1 is not quietly the one that always
    /// collects the odd student out.
    private static func smallestIndex<G: RandomNumberGenerator>(
        in buckets: [[UUID]], using rng: inout G
    ) -> Int {
        let smallest = buckets.map(\.count).min() ?? 0
        let candidates = buckets.indices.filter { buckets[$0].count == smallest }
        return candidates.randomElement(using: &rng) ?? 0
    }
}
