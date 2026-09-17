import Foundation

/// Per-class rules honoured by the constrained generator.
enum Constraint: Codable, Hashable {
    /// Unordered pair of students that must not end up adjacent.
    case keepApart(a: UUID, b: UUID)
    /// Student must sit in a given classroom row — portable across rooms.
    case rowPin(student: UUID, row: Int)
    /// Student must sit at one exact desk of one room.
    case seatPin(student: UUID, roomID: UUID, deskID: UUID)

    /// Canonical form of a keep-apart pair so unordered duplicates compare equal.
    static func keepApartPair(_ first: UUID, _ second: UUID) -> Constraint {
        first.uuidString <= second.uuidString
            ? .keepApart(a: first, b: second)
            : .keepApart(a: second, b: first)
    }

    var referencedStudents: [UUID] {
        switch self {
        case let .keepApart(a, b): [a, b]
        case let .rowPin(student, _): [student]
        case let .seatPin(student, _, _): [student]
        }
    }

    var referencedRoom: UUID? {
        if case let .seatPin(_, roomID, _) = self { return roomID }
        return nil
    }

    var referencedDesk: UUID? {
        if case let .seatPin(_, _, deskID) = self { return deskID }
        return nil
    }
}
