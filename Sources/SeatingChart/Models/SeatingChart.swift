import Foundation

/// Which desks count as neighbours for keep-apart checks.
enum AdjacencyMode: String, Codable, Hashable, CaseIterable, Identifiable {
    /// Left/right neighbours only.
    case relaxed
    /// Left/right plus directly in front and behind.
    case strict

    var id: String { rawValue }
}

enum GenerationMode: Codable, Hashable {
    case trueRandom
    case constrained(adjacency: AdjacencyMode)

    var isConstrained: Bool { if case .constrained = self { true } else { false } }

    var adjacency: AdjacencyMode? {
        if case let .constrained(adjacency) = self { return adjacency }
        return nil
    }
}

/// A generated assignment. One chart is kept per (class, room) pair.
struct SeatingChart: Codable, Identifiable, Hashable {
    var id: UUID
    var classID: UUID
    var roomID: UUID
    var mode: GenerationMode
    /// deskID → studentID
    var assignment: [UUID: UUID]
    var generatedAt: Date

    init(id: UUID = UUID(), classID: UUID, roomID: UUID, mode: GenerationMode,
         assignment: [UUID: UUID], generatedAt: Date = Date()) {
        self.id = id
        self.classID = classID
        self.roomID = roomID
        self.mode = mode
        self.assignment = assignment
        self.generatedAt = generatedAt
    }

    func student(atDesk deskID: UUID) -> UUID? { assignment[deskID] }

    func desk(ofStudent studentID: UUID) -> UUID? {
        assignment.first { $0.value == studentID }?.key
    }

    // MARK: - Codable
    //
    // `[UUID: UUID]` would encode as a flat array; a string-keyed object keeps
    // data.json readable.

    private enum CodingKeys: String, CodingKey {
        case id, classID, roomID, mode, assignment, generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        classID = try container.decode(UUID.self, forKey: .classID)
        roomID = try container.decode(UUID.self, forKey: .roomID)
        mode = try container.decode(GenerationMode.self, forKey: .mode)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let raw = try container.decode([String: String].self, forKey: .assignment)
        var mapped: [UUID: UUID] = [:]
        for (key, value) in raw {
            if let desk = UUID(uuidString: key), let student = UUID(uuidString: value) {
                mapped[desk] = student
            }
        }
        assignment = mapped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(classID, forKey: .classID)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(mode, forKey: .mode)
        try container.encode(generatedAt, forKey: .generatedAt)
        var raw: [String: String] = [:]
        for (desk, student) in assignment { raw[desk.uuidString] = student.uuidString }
        try container.encode(raw, forKey: .assignment)
    }
}
