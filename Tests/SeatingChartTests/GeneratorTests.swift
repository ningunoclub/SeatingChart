import Foundation
import Testing
@testable import SeatingChart

@Suite("Seating generator")
struct GeneratorTests {

    // MARK: - Preconditions

    @Test("Too few seats is rejected before any shuffling")
    func notEnoughSeats() {
        let schoolClass = Fixture.schoolClass(["A", "B", "C", "D", "E"])
        let room = Fixture.room(rows: 1, seatsPerRow: 4)
        var rng = SplitMix64(seed: 1)

        #expect(throws: GeneratorError.notEnoughSeats(students: 5, seats: 4)) {
            try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                          mode: .trueRandom, rng: &rng)
        }
    }

    @Test("Disabled desks do not count as seats")
    func disabledDesksDoNotCount() {
        var room = Fixture.room(rows: 1, seatsPerRow: 4)
        room.desks[0].isDisabled = true
        let schoolClass = Fixture.schoolClass(["A", "B", "C", "D"])
        var rng = SplitMix64(seed: 1)

        #expect(throws: GeneratorError.notEnoughSeats(students: 4, seats: 3)) {
            try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                          mode: .trueRandom, rng: &rng)
        }
    }

    @Test("An empty class is rejected")
    func emptyClassIsRejected() {
        var rng = SplitMix64(seed: 1)
        #expect(throws: GeneratorError.noStudents) {
            try SeatingGenerator.generate(schoolClass: Fixture.schoolClass([]),
                                          room: Fixture.room(rows: 1, seatsPerRow: 4),
                                          mode: .trueRandom, rng: &rng)
        }
    }

    // MARK: - True random

    @Test("True random seats every student exactly once on an enabled desk")
    func trueRandomSeatsEveryone() throws {
        let schoolClass = Fixture.schoolClass((1...20).map { "S\($0)" })
        var room = Fixture.room(rows: 4, seatsPerRow: 6)
        room.desks[3].isDisabled = true
        let enabled = Set(room.enabledDesks.map(\.id))

        for seed in UInt64(0)..<50 {
            var rng = SplitMix64(seed: seed)
            let chart = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                                      mode: .trueRandom, rng: &rng)
            #expect(chart.assignment.count == 20)
            #expect(Set(chart.assignment.values) == Set(schoolClass.students.map(\.id)))
            #expect(chart.assignment.keys.allSatisfy(enabled.contains))
        }
    }

    @Test("True random ignores keep-apart pairs and pins")
    func trueRandomIgnoresConstraints() throws {
        var schoolClass = Fixture.schoolClass(["Anna", "Ben"])
        let room = Fixture.room(rows: 1, seatsPerRow: 2)
        schoolClass.addKeepApart(Fixture.id(schoolClass, "Anna"), Fixture.id(schoolClass, "Ben"))
        var rng = SplitMix64(seed: 7)

        // Two adjacent seats and one keep-apart pair: only true random can fill this.
        let chart = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                                  mode: .trueRandom, rng: &rng)
        #expect(chart.assignment.count == 2)
    }

    @Test("Reruns feel different")
    func trueRandomVaries() throws {
        let schoolClass = Fixture.schoolClass((1...20).map { "S\($0)" })
        let room = Fixture.room(rows: 4, seatsPerRow: 6)
        var seen: Set<String> = []
        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            seen.insert(Fixture.signature(of: try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room, mode: .trueRandom, rng: &rng)))
        }
        #expect(seen.count > 15)
    }

    // MARK: - Constrained mode

    /// The core guarantee: 500 seeded runs per adjacency mode, never a keep-apart
    /// pair seated as neighbours.
    @Test("Keep-apart pairs are never seated as neighbours", arguments: AdjacencyMode.allCases)
    func keepApartIsNeverViolated(mode: AdjacencyMode) throws {
        var schoolClass = Fixture.schoolClass((1...22).map { "S\($0)" })
        let ids = schoolClass.students.map(\.id)
        schoolClass.addKeepApart(ids[0], ids[1])
        schoolClass.addKeepApart(ids[2], ids[3])
        schoolClass.addKeepApart(ids[4], ids[5])
        schoolClass.addKeepApart(ids[0], ids[6])
        schoolClass.addKeepApart(ids[7], ids[8])
        let room = Fixture.room(rows: 4, seatsPerRow: 6, aisleAfterSeat: 3)
        let adjacency = Adjacency(room: room, mode: mode)

        for seed in UInt64(0)..<500 {
            var rng = SplitMix64(seed: seed)
            let chart = try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room,
                mode: .constrained(adjacency: mode), rng: &rng)

            #expect(chart.assignment.count == 22)
            #expect(Set(chart.assignment.values).count == 22)
            for pair in schoolClass.keepApartPairs {
                let deskA = try #require(chart.desk(ofStudent: pair.a))
                let deskB = try #require(chart.desk(ofStudent: pair.b))
                #expect(!adjacency.areAdjacent(deskA, deskB),
                        "seed \(seed), mode \(mode): pair seated as neighbours")
            }
        }
    }

    @Test("Row pins land in the pinned row")
    func rowPinsAreHonored() throws {
        var schoolClass = Fixture.schoolClass((1...16).map { "S\($0)" })
        let ids = schoolClass.students.map(\.id)
        schoolClass.setRowPin(1, for: ids[0])
        schoolClass.setRowPin(1, for: ids[1])
        schoolClass.setRowPin(4, for: ids[2])
        schoolClass.addKeepApart(ids[0], ids[1])
        let room = Fixture.room(rows: 4, seatsPerRow: 4)

        for seed in UInt64(0)..<200 {
            var rng = SplitMix64(seed: seed)
            let chart = try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room,
                mode: .constrained(adjacency: .relaxed), rng: &rng)

            for pin in schoolClass.rowPins {
                let deskID = try #require(chart.desk(ofStudent: pin.student))
                let desk = try #require(room.desk(withID: deskID))
                #expect(room.row(of: desk) == pin.row, "seed \(seed)")
            }
        }
    }

    @Test("Row pins are measured in classroom rows, not grid rows")
    func rowPinsUseDerivedRows() throws {
        // Grid rows 0 and 3 hold desks; rows 1 and 2 are aisles, so the desks at
        // gridY 3 are classroom row 2.
        var schoolClass = Fixture.schoolClass(["Anna", "Ben"])
        let anna = Fixture.id(schoolClass, "Anna")
        schoolClass.setRowPin(2, for: anna)
        let room = Room(name: "Gapped", desks: [
            Desk(gridX: 0, gridY: 0), Desk(gridX: 1, gridY: 0),
            Desk(gridX: 0, gridY: 3), Desk(gridX: 1, gridY: 3),
        ])

        for seed in UInt64(0)..<50 {
            var rng = SplitMix64(seed: seed)
            let chart = try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room,
                mode: .constrained(adjacency: .relaxed), rng: &rng)
            let deskID = try #require(chart.desk(ofStudent: anna))
            let desk = try #require(room.desk(withID: deskID))
            #expect(desk.gridY == 3, "seed \(seed)")
        }
    }

    @Test("Seat pins land on exactly the pinned desk")
    func seatPinsAreHonored() throws {
        var schoolClass = Fixture.schoolClass((1...10).map { "S\($0)" })
        let ids = schoolClass.students.map(\.id)
        let room = Fixture.room(rows: 3, seatsPerRow: 4)
        let target = room.orderedDesks[5]
        schoolClass.setSeatPin(student: ids[3], roomID: room.id, deskID: target.id)

        for seed in UInt64(0)..<100 {
            var rng = SplitMix64(seed: seed)
            let chart = try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room,
                mode: .constrained(adjacency: .strict), rng: &rng)
            #expect(chart.assignment[target.id] == ids[3], "seed \(seed)")
        }
    }

    @Test("Seat pins belonging to another room are ignored")
    func seatPinForAnotherRoomIsIgnored() throws {
        var schoolClass = Fixture.schoolClass((1...6).map { "S\($0)" })
        let ids = schoolClass.students.map(\.id)
        let room = Fixture.room(rows: 2, seatsPerRow: 3)
        let otherRoom = Fixture.room(rows: 2, seatsPerRow: 3, name: "Other")
        schoolClass.setSeatPin(student: ids[0], roomID: otherRoom.id,
                               deskID: otherRoom.orderedDesks[0].id)

        var rng = SplitMix64(seed: 3)
        let chart = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                                  mode: .constrained(adjacency: .relaxed), rng: &rng)
        #expect(chart.assignment.count == 6)
    }

    // MARK: - Invalid pins

    @Test("A row pin beyond the room's rows is reported")
    func rowPinBeyondRoomIsRejected() {
        var schoolClass = Fixture.schoolClass(["Anna", "Ben"])
        let anna = Fixture.id(schoolClass, "Anna")
        schoolClass.setRowPin(5, for: anna)
        let room = Fixture.room(rows: 2, seatsPerRow: 3)
        var rng = SplitMix64(seed: 1)

        #expect(throws: GeneratorError.invalidPin(
            .rowMissing(student: anna, row: 5, availableRows: 2))) {
            try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                          mode: .constrained(adjacency: .relaxed), rng: &rng)
        }
    }

    @Test("A seat pin on a disabled desk is reported")
    func seatPinToDisabledDeskIsRejected() {
        var schoolClass = Fixture.schoolClass(["Anna", "Ben"])
        var room = Fixture.room(rows: 2, seatsPerRow: 3)
        room.desks[0].isDisabled = true
        let anna = Fixture.id(schoolClass, "Anna")
        schoolClass.setSeatPin(student: anna, roomID: room.id, deskID: room.desks[0].id)
        var rng = SplitMix64(seed: 1)

        #expect(throws: GeneratorError.invalidPin(.deskUnavailable(student: anna))) {
            try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                          mode: .constrained(adjacency: .relaxed), rng: &rng)
        }
    }

    @Test("Two students pinned to one desk is reported")
    func twoStudentsPinnedToOneDesk() {
        var schoolClass = Fixture.schoolClass(["Anna", "Ben"])
        let room = Fixture.room(rows: 2, seatsPerRow: 3)
        let desk = room.orderedDesks[0].id
        // Bypass setSeatPin's own de-duplication to simulate hand-edited data.
        schoolClass.constraints = [
            .seatPin(student: Fixture.id(schoolClass, "Anna"), roomID: room.id, deskID: desk),
            .seatPin(student: Fixture.id(schoolClass, "Ben"), roomID: room.id, deskID: desk),
        ]
        var rng = SplitMix64(seed: 1)

        Fixture.expectGeneratorError(schoolClass: schoolClass, room: room,
                                     mode: .constrained(adjacency: .relaxed), rng: &rng) { error in
            if case .invalidPin(.deskShared) = error { return true }
            return false
        }
    }

    @Test("A row pin that contradicts a seat pin is reported")
    func rowPinConflictingWithSeatPin() {
        var schoolClass = Fixture.schoolClass(["Anna", "Ben"])
        let room = Fixture.room(rows: 2, seatsPerRow: 3)
        let anna = Fixture.id(schoolClass, "Anna")
        schoolClass.setSeatPin(student: anna, roomID: room.id, deskID: room.orderedDesks[0].id)
        schoolClass.setRowPin(2, for: anna)
        var rng = SplitMix64(seed: 1)

        #expect(throws: GeneratorError.invalidPin(.rowAndSeatConflict(student: anna))) {
            try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                          mode: .constrained(adjacency: .relaxed), rng: &rng)
        }
    }

    // MARK: - Unsatisfiable

    @Test("An impossible set of rules fails fast, and names a pair")
    func unsatisfiableIsDetectedQuickly() {
        // Three mutually keep-apart students on three seats in a row: whoever sits
        // in the middle neighbours both ends.
        var schoolClass = Fixture.schoolClass(["A", "B", "C"])
        let ids = schoolClass.students.map(\.id)
        schoolClass.addKeepApart(ids[0], ids[1])
        schoolClass.addKeepApart(ids[1], ids[2])
        schoolClass.addKeepApart(ids[0], ids[2])
        let room = Fixture.room(rows: 1, seatsPerRow: 3)
        var rng = SplitMix64(seed: 1)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            Fixture.expectGeneratorError(schoolClass: schoolClass, room: room,
                                         mode: .constrained(adjacency: .relaxed), rng: &rng) { error in
                guard case let .unsatisfiable(conflict) = error else { return false }
                return conflict != nil   // the failing pair is identifiable here
            }
        }
        #expect(elapsed < .seconds(1), "must fail fast, not hang")
    }

    @Test("A row pin that cannot fit in its row is unsatisfiable, not a crash")
    func overfullPinnedRow() {
        var schoolClass = Fixture.schoolClass(["A", "B", "C"])
        let ids = schoolClass.students.map(\.id)
        for id in ids { schoolClass.setRowPin(1, for: id) }
        // Row 1 holds two desks; three students are pinned to it.
        let room = Room(name: "Small", desks: [
            Desk(gridX: 0, gridY: 0), Desk(gridX: 1, gridY: 0),
            Desk(gridX: 0, gridY: 1), Desk(gridX: 1, gridY: 1),
        ])
        var rng = SplitMix64(seed: 1)

        Fixture.expectGeneratorError(schoolClass: schoolClass, room: room,
                                     mode: .constrained(adjacency: .relaxed), rng: &rng) { error in
            if case .unsatisfiable = error { return true }
            return false
        }
    }

    @Test("A tight but solvable setup is solved on every seed")
    func hardButSolvableSetupSucceeds() throws {
        // 12 students on 12 strict-adjacent seats, six keep-apart pairs.
        var schoolClass = Fixture.schoolClass((1...12).map { "S\($0)" })
        let ids = schoolClass.students.map(\.id)
        for index in stride(from: 0, to: 12, by: 2) {
            schoolClass.addKeepApart(ids[index], ids[index + 1])
        }
        let room = Fixture.room(rows: 3, seatsPerRow: 4)
        let adjacency = Adjacency(room: room, mode: .strict)

        for seed in UInt64(0)..<100 {
            var rng = SplitMix64(seed: seed)
            let chart = try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room,
                mode: .constrained(adjacency: .strict), rng: &rng)
            for pair in schoolClass.keepApartPairs {
                let a = try #require(chart.desk(ofStudent: pair.a))
                let b = try #require(chart.desk(ofStudent: pair.b))
                #expect(!adjacency.areAdjacent(a, b), "seed \(seed)")
            }
        }
    }

    @Test("Constrained reruns also feel different")
    func constrainedRunsVary() throws {
        let schoolClass = Fixture.schoolClass((1...18).map { "S\($0)" })
        let room = Fixture.room(rows: 3, seatsPerRow: 6)
        var seen: Set<String> = []
        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            seen.insert(Fixture.signature(of: try SeatingGenerator.generate(
                schoolClass: schoolClass, room: room,
                mode: .constrained(adjacency: .relaxed), rng: &rng)))
        }
        #expect(seen.count > 15)
    }

    @Test("The same seed reproduces the same chart")
    func generationIsDeterministicForASeed() throws {
        let schoolClass = Fixture.schoolClass((1...15).map { "S\($0)" })
        let room = Fixture.room(rows: 3, seatsPerRow: 6)
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        let a = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                              mode: .constrained(adjacency: .relaxed), rng: &first)
        let b = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                              mode: .constrained(adjacency: .relaxed), rng: &second)
        #expect(a.assignment == b.assignment)
    }
}
