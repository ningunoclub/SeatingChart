import Foundation

/// An unordered pair of students named in an error message.
struct ConflictPair: Hashable {
    var a: UUID
    var b: UUID
}

enum InvalidPin: Hashable {
    /// A row pin names a row this room does not have.
    case rowMissing(student: UUID, row: Int, availableRows: Int)
    /// A seat pin names a desk that is missing or disabled in this room.
    case deskUnavailable(student: UUID)
    /// Two students are pinned to the same desk.
    case deskShared(student: UUID, other: UUID)
    /// One student is pinned to two different desks in the same room.
    case studentPinnedTwice(student: UUID)
    /// A student's row pin and seat pin point at different rows.
    case rowAndSeatConflict(student: UUID)
}

enum GeneratorError: Error, Hashable {
    case noStudents
    case notEnoughSeats(students: Int, seats: Int)
    case invalidPin(InvalidPin)
    /// Backtracking exhausted. `conflict` names one keep-apart pair when the
    /// solver could attribute the failure to one.
    case unsatisfiable(conflict: ConflictPair?)
}

extension GeneratorError {
    /// Localized, human-readable text — resolves ids to student names.
    func message(in schoolClass: SchoolClass, room: Room) -> String {
        func name(_ id: UUID) -> String { schoolClass.name(of: id) ?? L("error.unknown_student") }

        switch self {
        case .noStudents:
            return L("error.no_students")

        case let .notEnoughSeats(students, seats):
            return L("error.not_enough_seats", students, seats)

        case let .invalidPin(reason):
            switch reason {
            case let .rowMissing(student, row, availableRows):
                return L("error.pin.row_missing", name(student), row, availableRows)
            case let .deskUnavailable(student):
                return L("error.pin.desk_unavailable", name(student))
            case let .deskShared(student, other):
                return L("error.pin.desk_shared", name(student), name(other))
            case let .studentPinnedTwice(student):
                return L("error.pin.student_twice", name(student))
            case let .rowAndSeatConflict(student):
                return L("error.pin.row_seat_conflict", name(student))
            }

        case let .unsatisfiable(conflict):
            if let conflict {
                return L("error.unsatisfiable_pair", name(conflict.a), name(conflict.b))
            }
            return L("error.unsatisfiable")
        }
    }
}
