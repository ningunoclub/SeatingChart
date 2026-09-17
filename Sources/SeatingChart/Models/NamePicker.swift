import Foundation

/// What the overlay shows for the picked student.
enum PickerDisplayMode: String, Codable, CaseIterable, Identifiable {
    case name
    case photo
    case both

    var id: String { rawValue }
}

/// Drawing a random student. Pure functions so the interesting part — "everyone
/// gets a turn before anyone repeats" — is testable without any UI.
enum NameDraw {
    /// Students still owed a turn this round. Derived from the live class every
    /// call, so students added mid-round join the pool and deleted ones vanish.
    static func remaining(in students: [Student], picked: [UUID]) -> [Student] {
        let alreadyPicked = Set(picked)
        return students.filter { !alreadyPicked.contains($0.id) }
    }

    /// How many of the current class have had a turn. Ignores ids left over from
    /// students who have since been deleted.
    static func pickedCount(in students: [Student], picked: [UUID]) -> Int {
        students.count - remaining(in: students, picked: picked).count
    }

    static func next(from students: [Student], picked: [UUID],
                     avoidRepeats: Bool) -> (winner: UUID, picked: [UUID])? {
        var rng = SystemRandomNumberGenerator()
        return next(from: students, picked: picked, avoidRepeats: avoidRepeats, using: &rng)
    }

    /// The winner plus the round's new picked-list. With `avoidRepeats` on, an
    /// exhausted round resets itself so the next draw starts a fresh one.
    static func next<G: RandomNumberGenerator>(
        from students: [Student],
        picked: [UUID],
        avoidRepeats: Bool,
        using rng: inout G
    ) -> (winner: UUID, picked: [UUID])? {
        guard !students.isEmpty else { return nil }

        guard avoidRepeats else {
            guard let winner = students.randomElement(using: &rng) else { return nil }
            // The round is only about repeat-avoidance, so leave it untouched.
            return (winner.id, picked)
        }

        let memberIDs = Set(students.map(\.id))
        var round = picked.filter { memberIDs.contains($0) }
        var pool = remaining(in: students, picked: round)
        if pool.isEmpty {
            // Everyone has had a turn — start over.
            round = []
            pool = students
        }
        guard let winner = pool.randomElement(using: &rng) else { return nil }
        return (winner.id, round + [winner.id])
    }
}
