import Foundation
import Testing
@testable import SeatingChart

@Suite("Persistence")
final class PersistenceTests {
    private let root: URL
    private let persistence: Persistence

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SeatingChartTests-\(UUID().uuidString)", isDirectory: true)
        persistence = Persistence(rootDirectory: root)
        try persistence.ensureDirectories()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("A fresh install loads an empty document")
    func emptyStoreLoadsEmpty() throws {
        let document = try persistence.load()
        #expect(document.schemaVersion == Persistence.schemaVersion)
        #expect(document.classes.isEmpty)
        #expect(document.rooms.isEmpty)
        #expect(document.charts.isEmpty)
    }

    @Test("Save then load preserves classes, rooms, constraints and charts")
    func roundTripPreservesEverything() throws {
        var room = Fixture.room(rows: 3, seatsPerRow: 4, aisleAfterSeat: 2)
        room.desks[2].isDisabled = true

        var schoolClass = Fixture.schoolClass(["Anna", "Ben", "Chiara"])
        let anna = Fixture.id(schoolClass, "Anna")
        let ben = Fixture.id(schoolClass, "Ben")
        schoolClass.students[0].photoFileName = "\(anna.uuidString).jpg"
        schoolClass.addKeepApart(anna, ben)
        schoolClass.setRowPin(2, for: ben)
        schoolClass.setSeatPin(student: anna, roomID: room.id, deskID: room.orderedDesks[0].id)

        let chart = SeatingChart(classID: schoolClass.id, roomID: room.id,
                                 mode: .constrained(adjacency: .strict),
                                 assignment: [room.orderedDesks[0].id: anna,
                                              room.orderedDesks[1].id: ben])

        try persistence.save(DataFile(classes: [schoolClass], rooms: [room], charts: [chart]))
        let loaded = try persistence.load()

        #expect(loaded.classes == [schoolClass])
        #expect(loaded.rooms == [room])
        #expect(loaded.charts.count == 1)
        #expect(loaded.charts[0].id == chart.id)
        #expect(loaded.charts[0].assignment == chart.assignment)
        #expect(loaded.charts[0].mode == .constrained(adjacency: .strict))
        #expect(abs(loaded.charts[0].generatedAt.timeIntervalSince(chart.generatedAt)) < 1.0)
    }

    @Test("A data.json written before genders existed still loads")
    func decodesFileWithoutGenders() throws {
        // Verbatim shape of a pre-gender file: the key is simply absent.
        let json = """
        {
          "schemaVersion": 1,
          "classes": [
            {
              "id": "\(UUID().uuidString)",
              "name": "5a",
              "students": [
                { "id": "\(UUID().uuidString)", "firstName": "Anna" },
                { "id": "\(UUID().uuidString)", "firstName": "Ben",
                  "photoFileName": "ben.jpg" }
              ],
              "constraints": []
            }
          ],
          "rooms": [],
          "charts": []
        }
        """
        try Data(json.utf8).write(to: persistence.dataFileURL)

        let loaded = try persistence.load()
        let students = try #require(loaded.classes.first).students
        #expect(students.count == 2)
        #expect(students.allSatisfy { $0.gender == .unspecified })
        #expect(students[1].photoFileName == "ben.jpg")
    }

    @Test("data.json stays human-readable")
    func dataFileIsReadableJSON() throws {
        let room = Fixture.room(rows: 1, seatsPerRow: 2)
        let schoolClass = Fixture.schoolClass(["Anna"])
        let chart = SeatingChart(classID: schoolClass.id, roomID: room.id, mode: .trueRandom,
                                 assignment: [room.orderedDesks[0].id: schoolClass.students[0].id])
        try persistence.save(DataFile(classes: [schoolClass], rooms: [room], charts: [chart]))

        let text = try String(contentsOf: persistence.dataFileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.contains("Anna"))
        #expect(text.contains(room.orderedDesks[0].id.uuidString),
                "the assignment should use string keys, not a flattened array")
    }

    @Test("Writes are atomic, so the previous file survives a failed write")
    func savesAreAtomic() throws {
        let room = Fixture.room(rows: 1, seatsPerRow: 2)
        try persistence.save(DataFile(rooms: [room]))
        let firstSize = try Data(contentsOf: persistence.dataFileURL).count
        try persistence.save(DataFile(rooms: [room, Fixture.room(rows: 2, seatsPerRow: 4)]))
        let secondSize = try Data(contentsOf: persistence.dataFileURL).count
        #expect(secondSize > firstSize)
        #expect(try persistence.load().rooms.count == 2)
    }

    @Test("Loading prunes constraints for deleted students, desks and rooms")
    func loadPrunesDanglingConstraints() throws {
        let room = Fixture.room(rows: 2, seatsPerRow: 2)
        var schoolClass = Fixture.schoolClass(["Anna"])
        let anna = Fixture.id(schoolClass, "Anna")
        let ghost = UUID()
        schoolClass.constraints = [
            .keepApart(a: anna, b: ghost),                                     // deleted student
            .rowPin(student: ghost, row: 1),                                   // deleted student
            .seatPin(student: anna, roomID: room.id, deskID: UUID()),          // deleted desk
            .seatPin(student: anna, roomID: UUID(), deskID: room.desks[0].id), // deleted room
            .rowPin(student: anna, row: 1),                                    // valid
        ]
        try persistence.save(DataFile(classes: [schoolClass], rooms: [room]))

        let loaded = try persistence.load()
        #expect(loaded.classes[0].constraints == [.rowPin(student: anna, row: 1)])
    }

    @Test("Loading drops orphaned charts and stale seat assignments")
    func loadPrunesCharts() throws {
        let room = Fixture.room(rows: 1, seatsPerRow: 2)
        let schoolClass = Fixture.schoolClass(["Anna"])
        let anna = schoolClass.students[0].id
        let orphan = SeatingChart(classID: UUID(), roomID: room.id, mode: .trueRandom, assignment: [:])
        let stale = SeatingChart(classID: schoolClass.id, roomID: room.id, mode: .trueRandom,
                                 assignment: [room.desks[0].id: anna,
                                              room.desks[1].id: UUID()])  // deleted student
        try persistence.save(DataFile(classes: [schoolClass], rooms: [room], charts: [orphan, stale]))

        let loaded = try persistence.load()
        #expect(loaded.charts.count == 1)
        #expect(loaded.charts[0].assignment == [room.desks[0].id: anna])
    }

    @Test("Seat numbering round-trips, and older rooms load as front-left")
    func seatNumberingRoundTrips() throws {
        var room = Fixture.room(rows: 2, seatsPerRow: 3)
        room.seatNumbering = .frontRight
        try persistence.save(DataFile(rooms: [room]))
        #expect(try persistence.load().rooms[0].seatNumbering == .frontRight)

        // A room written before the setting existed has no such key.
        let legacy = """
        {"schemaVersion": 1, "classes": [], "charts": [], "rooms": [
          {"id": "\(UUID().uuidString)", "name": "Old room", "desks": []}
        ]}
        """
        try legacy.write(to: persistence.dataFileURL, atomically: true, encoding: .utf8)
        let loaded = try persistence.load()
        #expect(loaded.rooms.count == 1)
        #expect(loaded.rooms[0].seatNumbering == .frontLeft)
    }

    @Test("A newer schema version is refused rather than misread")
    func futureSchemaIsRefused() throws {
        let json = #"{"schemaVersion": 99, "classes": [], "rooms": [], "charts": []}"#
        try json.write(to: persistence.dataFileURL, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try persistence.load() }
    }

    @Test("Photos are copied in, normalised by extension, and replaced cleanly")
    func photoImportCopiesAndReplaces() throws {
        let studentID = UUID()
        let source = root.appendingPathComponent("portrait.PNG")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let name = try persistence.importPhoto(from: source, for: studentID)
        #expect(name == "\(studentID.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: persistence.photoURL(named: name).path))
        #expect(FileManager.default.fileExists(atPath: source.path),
                "the original is copied, not moved")

        // Replacing with a different format removes the previous file.
        let jpeg = root.appendingPathComponent("portrait.jpg")
        try Data([0xFF, 0xD8]).write(to: jpeg)
        let replaced = try persistence.importPhoto(from: jpeg, for: studentID)
        #expect(replaced == "\(studentID.uuidString).jpg")
        #expect(!FileManager.default.fileExists(atPath: persistence.photoURL(named: name).path))

        persistence.deleteAllPhotos(for: studentID)
        #expect(!FileManager.default.fileExists(atPath: persistence.photoURL(named: replaced).path))
    }

    @Test("An unknown image extension falls back to png")
    func unknownExtensionFallsBack() throws {
        let studentID = UUID()
        let source = root.appendingPathComponent("scan.weird")
        try Data([0x00]).write(to: source)
        #expect(try persistence.importPhoto(from: source, for: studentID)
                == "\(studentID.uuidString).png")
    }
}
