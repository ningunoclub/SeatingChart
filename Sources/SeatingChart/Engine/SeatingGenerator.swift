import Foundation

/// Small, fast, seedable generator so tests can reproduce a run exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Pure seating solver — no UI dependencies.
enum SeatingGenerator {
    /// Fresh-shuffle restarts before giving up.
    static let restartLimit = 200
    /// Global cap on assignment attempts, so an unsatisfiable setup fails fast.
    static let stepBudget = 200_000

    static func generate(schoolClass: SchoolClass, room: Room, mode: GenerationMode) throws -> SeatingChart {
        var rng = SystemRandomNumberGenerator()
        return try generate(schoolClass: schoolClass, room: room, mode: mode, rng: &rng)
    }

    static func generate<G: RandomNumberGenerator>(
        schoolClass: SchoolClass,
        room: Room,
        mode: GenerationMode,
        rng: inout G
    ) throws -> SeatingChart {
        // Derive a local generator so the recursive search can capture it.
        var random = SplitMix64(seed: rng.next())

        let students = schoolClass.students
        guard !students.isEmpty else { throw GeneratorError.noStudents }

        let seats = room.enabledDesks
        guard seats.count >= students.count else {
            throw GeneratorError.notEnoughSeats(students: students.count, seats: seats.count)
        }

        switch mode {
        case .trueRandom:
            let shuffled = students.shuffled(using: &random)
            var assignment: [UUID: UUID] = [:]
            for (index, desk) in seats.enumerated() where index < shuffled.count {
                assignment[desk.id] = shuffled[index].id
            }
            return SeatingChart(classID: schoolClass.id, roomID: room.id,
                                mode: mode, assignment: assignment)

        case let .constrained(adjacencyMode):
            let assignment = try solve(schoolClass: schoolClass, room: room,
                                       adjacencyMode: adjacencyMode, random: &random)
            return SeatingChart(classID: schoolClass.id, roomID: room.id,
                                mode: mode, assignment: assignment)
        }
    }

    // MARK: - Constrained solve

    private static func solve(
        schoolClass: SchoolClass,
        room: Room,
        adjacencyMode: AdjacencyMode,
        random: inout SplitMix64
    ) throws -> [UUID: UUID] {
        let students = schoolClass.students
        let studentIDs = Set(students.map(\.id))
        let seats = room.enabledDesks
        let seatByID = Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0) })

        // 1a. Seat pins for this room become fixed placements.
        var fixed: [UUID: UUID] = [:]        // deskID → studentID
        var deskOfPinned: [UUID: UUID] = [:] // studentID → deskID
        for pin in schoolClass.seatPins(inRoom: room.id) {
            guard studentIDs.contains(pin.student) else { continue } // dangling, ignored
            guard seatByID[pin.deskID] != nil else {
                throw GeneratorError.invalidPin(.deskUnavailable(student: pin.student))
            }
            if let other = fixed[pin.deskID], other != pin.student {
                throw GeneratorError.invalidPin(.deskShared(student: pin.student, other: other))
            }
            if let existing = deskOfPinned[pin.student], existing != pin.deskID {
                throw GeneratorError.invalidPin(.studentPinnedTwice(student: pin.student))
            }
            fixed[pin.deskID] = pin.student
            deskOfPinned[pin.student] = pin.deskID
        }

        // 1b. Row pins must name a row this room actually has.
        let rowCount = room.rowCount
        var rowPin: [UUID: Int] = [:]
        for pin in schoolClass.rowPins {
            guard studentIDs.contains(pin.student) else { continue }
            guard pin.row >= 1, pin.row <= rowCount else {
                throw GeneratorError.invalidPin(
                    .rowMissing(student: pin.student, row: pin.row, availableRows: rowCount))
            }
            rowPin[pin.student] = pin.row
        }
        for (student, deskID) in deskOfPinned {
            guard let row = rowPin[student], let desk = seatByID[deskID] else { continue }
            guard room.row(of: desk) == row else {
                throw GeneratorError.invalidPin(.rowAndSeatConflict(student: student))
            }
        }

        // 2. Keep-apart graph and neighbour map.
        var conflicts: [UUID: Set<UUID>] = [:]
        for pair in schoolClass.keepApartPairs where pair.a != pair.b {
            guard studentIDs.contains(pair.a), studentIDs.contains(pair.b) else { continue }
            conflicts[pair.a, default: []].insert(pair.b)
            conflicts[pair.b, default: []].insert(pair.a)
        }
        let adjacency = Adjacency(room: room, mode: adjacencyMode)

        // 3. Candidate desks per unplaced student; row pins shrink the domain.
        let freeDesks = seats.filter { fixed[$0.id] == nil }
        let unplaced = students.filter { deskOfPinned[$0.id] == nil }
        var domains: [UUID: [UUID]] = [:]
        for student in unplaced {
            if let row = rowPin[student.id] {
                let inRow = freeDesks.filter { room.row(of: $0) == row }.map(\.id)
                guard !inRow.isEmpty else {
                    throw GeneratorError.unsatisfiable(conflict: nil)
                }
                domains[student.id] = inRow
            } else {
                domains[student.id] = freeDesks.map(\.id)
            }
        }

        if unplaced.isEmpty { return fixed }

        // 4. Randomised backtracking with restarts and a global step budget.
        var steps = 0
        var deepestFailure: UUID?
        var bestDepth = -1

        for _ in 0..<restartLimit {
            // Tie-break randomly, but keep a deterministic total order per restart.
            var tiebreak: [UUID: UInt64] = [:]
            for student in unplaced { tiebreak[student.id] = random.next() }
            let order = unplaced.map(\.id).sorted { lhs, rhs in
                let lCount = domains[lhs]?.count ?? 0
                let rCount = domains[rhs]?.count ?? 0
                if lCount != rCount { return lCount < rCount }     // smallest domain first
                let lDegree = conflicts[lhs]?.count ?? 0
                let rDegree = conflicts[rhs]?.count ?? 0
                if lDegree != rDegree { return lDegree > rDegree } // most constrained first
                return tiebreak[lhs]! < tiebreak[rhs]!
            }

            var assignment = fixed
            var taken = Set(fixed.keys)

            func fits(_ student: UUID, at deskID: UUID) -> Bool {
                guard let foes = conflicts[student], !foes.isEmpty else { return true }
                for neighbor in adjacency.neighbors(of: deskID) {
                    if let occupant = assignment[neighbor], foes.contains(occupant) { return false }
                }
                return true
            }

            func search(_ index: Int) -> Bool {
                if index == order.count { return true }
                if steps > stepBudget { return false }
                let student = order[index]
                var candidates = (domains[student] ?? []).filter { !taken.contains($0) }
                candidates.shuffle(using: &random)
                for deskID in candidates {
                    steps += 1
                    guard fits(student, at: deskID) else { continue }
                    assignment[deskID] = student
                    taken.insert(deskID)
                    if search(index + 1) { return true }
                    assignment[deskID] = nil
                    taken.remove(deskID)
                    if steps > stepBudget { return false }
                }
                if index > bestDepth {
                    bestDepth = index
                    deepestFailure = student
                }
                return false
            }

            if search(0) { return assignment }
            if steps > stepBudget { break }
        }

        var conflict: ConflictPair?
        if let student = deepestFailure, let foe = conflicts[student]?.sorted(by: {
            $0.uuidString < $1.uuidString
        }).first {
            conflict = ConflictPair(a: student, b: foe)
        }
        throw GeneratorError.unsatisfiable(conflict: conflict)
    }
}
