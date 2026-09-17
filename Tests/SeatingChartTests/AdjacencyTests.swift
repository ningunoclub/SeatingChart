import Testing
@testable import SeatingChart

@Suite("Adjacency and room geometry")
struct AdjacencyTests {

    @Test("Relaxed mode links side neighbours only")
    func sideNeighborsOnly() {
        let room = Fixture.room(rows: 2, seatsPerRow: 3)
        let desks = room.orderedDesks
        let adjacency = Adjacency(room: room, mode: .relaxed)

        #expect(adjacency.areAdjacent(desks[0].id, desks[1].id))
        #expect(adjacency.areAdjacent(desks[1].id, desks[2].id))
        #expect(!adjacency.areAdjacent(desks[0].id, desks[2].id), "not neighbours across a seat")
        #expect(!adjacency.areAdjacent(desks[0].id, desks[3].id), "front/behind is relaxed-mode exempt")
    }

    @Test("Strict mode adds front and behind, but never diagonals")
    func strictAddsFrontAndBehind() {
        let room = Fixture.room(rows: 2, seatsPerRow: 3)
        let desks = room.orderedDesks
        let adjacency = Adjacency(room: room, mode: .strict)

        #expect(adjacency.areAdjacent(desks[0].id, desks[3].id))
        #expect(adjacency.areAdjacent(desks[3].id, desks[0].id))
        #expect(!adjacency.areAdjacent(desks[0].id, desks[4].id))
    }

    @Test("A gap in the grid breaks adjacency")
    func gapBreaksAdjacency() {
        let room = Room(name: "Pairs", desks: [
            Desk(gridX: 0, gridY: 0), Desk(gridX: 1, gridY: 0),
            Desk(gridX: 3, gridY: 0), Desk(gridX: 4, gridY: 0),
        ])
        let desks = room.orderedDesks
        let adjacency = Adjacency(room: room, mode: .strict)

        #expect(adjacency.areAdjacent(desks[0].id, desks[1].id))
        #expect(adjacency.areAdjacent(desks[2].id, desks[3].id))
        #expect(!adjacency.areAdjacent(desks[1].id, desks[2].id), "the aisle separates the pairs")
    }

    @Test("Disabled desks are excluded from the neighbour map")
    func disabledDesksAreNotNeighbours() {
        var room = Fixture.room(rows: 1, seatsPerRow: 3)
        room.desks[1].isDisabled = true
        let desks = room.orderedDesks
        let adjacency = Adjacency(room: room, mode: .relaxed)

        #expect(adjacency.neighbors(of: desks[0].id).isEmpty)
        #expect(!adjacency.areAdjacent(desks[0].id, desks[2].id))
    }

    @Test("Row numbers skip empty grid rows, so row 1 is always the front row")
    func rowNumbersSkipEmptyGridRows() {
        let room = Room(name: "Gapped", desks: [
            Desk(gridX: 0, gridY: 0),
            Desk(gridX: 0, gridY: 2),
        ])
        #expect(room.rowCount == 2)
        #expect(room.row(of: room.orderedDesks[0]) == 1)
        #expect(room.row(of: room.orderedDesks[1]) == 2)
    }

    @Test("Disabled desks keep their seat number")
    func seatNumbersStayStableWhenDisabling() {
        var room = Fixture.room(rows: 2, seatsPerRow: 2)
        let before = room.seatNumbers
        room.desks[0].isDisabled = true
        #expect(before == room.seatNumbers)
    }

    @Test("Front-right numbering flips each row, but rows still start at the blackboard")
    func frontRightNumbering() {
        var room = Fixture.room(rows: 2, seatsPerRow: 3)
        let left = room.seatNumbers
        let byPosition = Dictionary(uniqueKeysWithValues: room.desks.map { ($0.id, ($0.gridX, $0.gridY)) })

        // Front-left: seat 1 is (x0, y0), seat 3 is (x2, y0), seat 4 is (x0, y1).
        #expect(left.first { $0.value == 1 }.map { byPosition[$0.key]! } ?? (-1, -1) == (0, 0))
        #expect(left.first { $0.value == 4 }.map { byPosition[$0.key]! } ?? (-1, -1) == (0, 1))

        room.seatNumbering = .frontRight
        let right = room.seatNumbers
        // Front-right: seat 1 is (x2, y0), seat 3 is (x0, y0), seat 4 is (x2, y1).
        #expect(right.first { $0.value == 1 }.map { byPosition[$0.key]! } ?? (-1, -1) == (2, 0))
        #expect(right.first { $0.value == 3 }.map { byPosition[$0.key]! } ?? (-1, -1) == (0, 0))
        #expect(right.first { $0.value == 4 }.map { byPosition[$0.key]! } ?? (-1, -1) == (2, 1))
    }

    @Test("Numbering direction changes neither rows nor neighbours")
    func numberingDoesNotAffectGeometry() {
        var room = Fixture.room(rows: 2, seatsPerRow: 3, aisleAfterSeat: 1)
        let frontDesk = room.desks.first { $0.gridX == 0 && $0.gridY == 0 }!
        let neighbour = room.desks.first { $0.gridX == 2 && $0.gridY == 0 }!
        let rowsBefore = room.rowCount
        let adjacentBefore = Adjacency(room: room, mode: .strict).areAdjacent(frontDesk.id, neighbour.id)

        room.seatNumbering = .frontRight

        #expect(room.rowCount == rowsBefore)
        #expect(room.row(of: frontDesk) == 1, "row 1 is still the row at the blackboard")
        #expect(Adjacency(room: room, mode: .strict).areAdjacent(frontDesk.id, neighbour.id)
                == adjacentBefore)
        #expect(Set(room.enabledDesks.map(\.id)) == Set(room.desks.map(\.id)))
    }

    @Test("Front-right numbering still skips disabled desks consistently")
    func frontRightWithDisabledDesk() {
        var room = Fixture.room(rows: 1, seatsPerRow: 3)
        room.seatNumbering = .frontRight
        let before = room.seatNumbers
        room.desks[0].isDisabled = true
        #expect(before == room.seatNumbers, "disabled desks keep their number")
        #expect(room.enabledDesks.count == 2)
    }

    @Test("An aisle column shifts seat numbering but not row numbering")
    func aisleLayout() {
        let room = Fixture.room(rows: 2, seatsPerRow: 4, aisleAfterSeat: 2)
        #expect(room.desks.count == 8)
        #expect(room.rowCount == 2)
        #expect(room.gridWidth == 5, "one empty column was inserted")
        let front = room.enabledDesks(inRow: 1)
        #expect(front.map(\.gridX) == [0, 1, 3, 4])
    }
}
