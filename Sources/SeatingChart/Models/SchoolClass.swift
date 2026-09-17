import Foundation

struct SchoolClass: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var students: [Student]
    var constraints: [Constraint]

    init(id: UUID = UUID(), name: String, students: [Student] = [], constraints: [Constraint] = []) {
        self.id = id
        self.name = name
        self.students = students
        self.constraints = constraints
    }

    func student(_ id: UUID) -> Student? { students.first { $0.id == id } }

    func name(of studentID: UUID) -> String? { student(studentID)?.firstName }

    var keepApartPairs: [(a: UUID, b: UUID)] {
        constraints.compactMap { if case let .keepApart(a, b) = $0 { (a, b) } else { nil } }
    }

    func rowPin(for studentID: UUID) -> Int? {
        for case let .rowPin(student, row) in constraints where student == studentID { return row }
        return nil
    }

    var rowPins: [(student: UUID, row: Int)] {
        constraints.compactMap { if case let .rowPin(s, r) = $0 { (s, r) } else { nil } }
    }

    func seatPins(inRoom roomID: UUID) -> [(student: UUID, deskID: UUID)] {
        constraints.compactMap {
            if case let .seatPin(s, room, desk) = $0, room == roomID { (s, desk) } else { nil }
        }
    }

    var seatPins: [(student: UUID, roomID: UUID, deskID: UUID)] {
        constraints.compactMap { if case let .seatPin(s, r, d) = $0 { (s, r, d) } else { nil } }
    }

    // MARK: - Mutation helpers

    mutating func removeConstraints(where predicate: (Constraint) -> Bool) {
        constraints.removeAll(where: predicate)
    }

    /// Drops constraints that point at students no longer in the class.
    mutating func pruneDanglingConstraints() {
        let ids = Set(students.map(\.id))
        constraints.removeAll { !$0.referencedStudents.allSatisfy(ids.contains) }
        // A keep-apart pair of one student with itself is meaningless.
        constraints.removeAll { if case let .keepApart(a, b) = $0 { a == b } else { false } }
    }

    mutating func setRowPin(_ row: Int?, for studentID: UUID) {
        constraints.removeAll { if case let .rowPin(s, _) = $0 { s == studentID } else { false } }
        if let row { constraints.append(.rowPin(student: studentID, row: row)) }
    }

    mutating func setSeatPin(student studentID: UUID, roomID: UUID, deskID: UUID) {
        // One pin per student per room, and one student per pinned desk.
        constraints.removeAll {
            if case let .seatPin(s, r, d) = $0 { r == roomID && (s == studentID || d == deskID) }
            else { false }
        }
        constraints.append(.seatPin(student: studentID, roomID: roomID, deskID: deskID))
    }

    mutating func removeSeatPin(roomID: UUID, deskID: UUID) {
        constraints.removeAll {
            if case let .seatPin(_, r, d) = $0 { r == roomID && d == deskID } else { false }
        }
    }

    @discardableResult
    mutating func addKeepApart(_ first: UUID, _ second: UUID) -> Bool {
        guard first != second else { return false }
        let pair = Constraint.keepApartPair(first, second)
        guard !constraints.contains(pair) else { return false }
        constraints.append(pair)
        return true
    }
}
