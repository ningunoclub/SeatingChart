import Foundation

/// Which front corner seat number 1 sits in. Rows are always numbered from the
/// blackboard; this only flips the direction within each row.
enum SeatNumbering: String, Codable, Hashable, CaseIterable, Identifiable {
    case frontLeft
    case frontRight

    var id: String { rawValue }
}

/// One desk on the room's editing grid. `gridY == 0` is closest to the blackboard.
struct Desk: Codable, Identifiable, Hashable {
    var id: UUID
    var gridX: Int
    var gridY: Int
    /// Empty-seat control: a disabled desk is never assigned a student.
    var isDisabled: Bool

    init(id: UUID = UUID(), gridX: Int, gridY: Int, isDisabled: Bool = false) {
        self.id = id
        self.gridX = gridX
        self.gridY = gridY
        self.isDisabled = isDisabled
    }
}

struct Room: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var desks: [Desk]
    /// Which front corner seat 1 sits in.
    var seatNumbering: SeatNumbering

    init(id: UUID = UUID(), name: String, desks: [Desk] = [],
         seatNumbering: SeatNumbering = .frontLeft) {
        self.id = id
        self.name = name
        self.desks = desks
        self.seatNumbering = seatNumbering
    }

    // Explicit decoding so rooms saved before seat numbering was configurable
    // still load, as front-left.
    enum CodingKeys: String, CodingKey {
        case id, name, desks, seatNumbering
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        desks = try container.decode([Desk].self, forKey: .desks)
        seatNumbering = try container.decodeIfPresent(SeatNumbering.self, forKey: .seatNumbering)
            ?? .frontLeft
    }

    // MARK: - Derived geometry

    /// Desks in seat-number order: by grid row from the blackboard back, then
    /// across the row in the direction `seatNumbering` picks.
    var orderedDesks: [Desk] {
        switch seatNumbering {
        case .frontLeft:
            return desks.sorted { ($0.gridY, $0.gridX) < ($1.gridY, $1.gridX) }
        case .frontRight:
            return desks.sorted { ($0.gridY, -$0.gridX) < ($1.gridY, -$1.gridX) }
        }
    }

    /// Seat numbers 1…n. Disabled desks keep their number so numbering stays
    /// stable while toggling.
    var seatNumbers: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (index, desk) in orderedDesks.enumerated() { result[desk.id] = index + 1 }
        return result
    }

    func seatNumber(of deskID: UUID) -> Int? { seatNumbers[deskID] }

    var enabledDesks: [Desk] { orderedDesks.filter { !$0.isDisabled } }

    /// Grid row → 1-based classroom row. Empty grid rows (aisles) are skipped, so
    /// row 1 is always the front row.
    var rowByGridY: [Int: Int] {
        let ys = Set(enabledDesks.map(\.gridY)).sorted()
        var result: [Int: Int] = [:]
        for (index, y) in ys.enumerated() { result[y] = index + 1 }
        return result
    }

    var rowCount: Int { Set(enabledDesks.map(\.gridY)).count }

    func row(of desk: Desk) -> Int? { rowByGridY[desk.gridY] }

    func enabledDesks(inRow row: Int) -> [Desk] {
        let map = rowByGridY
        return enabledDesks.filter { map[$0.gridY] == row }
    }

    func desk(withID id: UUID) -> Desk? { desks.first { $0.id == id } }

    func desk(atX x: Int, y: Int) -> Desk? {
        desks.first { $0.gridX == x && $0.gridY == y }
    }

    var gridWidth: Int { (desks.map(\.gridX).max() ?? -1) + 1 }
    var gridHeight: Int { (desks.map(\.gridY).max() ?? -1) + 1 }

    // MARK: - Layout generation

    /// Builds a regular layout: `rows` × `seatsPerRow`, optionally inserting an
    /// empty grid column (aisle) after seat `aisleAfterSeat` of every row.
    static func regularLayout(rows: Int, seatsPerRow: Int, aisleAfterSeat: Int?) -> [Desk] {
        var desks: [Desk] = []
        for y in 0..<max(0, rows) {
            var x = 0
            for seat in 1...max(1, seatsPerRow) {
                desks.append(Desk(gridX: x, gridY: y))
                x += 1
                if let aisle = aisleAfterSeat, aisle > 0, seat == aisle { x += 1 }
            }
        }
        return desks
    }
}
