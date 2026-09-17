import Foundation
import Testing
@testable import SeatingChart

@Suite("Import & export")
struct BundleTests {

    // MARK: - Fixtures

    /// A class with one of every constraint, a room with a disabled desk and a
    /// non-default numbering, and one chart tying them together.
    private func sampleDocument() -> (DataFile, SchoolClass, Room, SeatingChart) {
        var room = Fixture.room(rows: 3, seatsPerRow: 4, aisleAfterSeat: 2)
        room.seatNumbering = .frontRight
        room.desks[2].isDisabled = true

        var schoolClass = Fixture.schoolClass(["Anna", "Ben", "Chiara"])
        let anna = Fixture.id(schoolClass, "Anna")
        let ben = Fixture.id(schoolClass, "Ben")
        schoolClass.addKeepApart(anna, ben)
        schoolClass.setRowPin(2, for: ben)
        schoolClass.setSeatPin(student: anna, roomID: room.id, deskID: room.orderedDesks[0].id)

        let chart = SeatingChart(classID: schoolClass.id, roomID: room.id,
                                 mode: .constrained(adjacency: .strict),
                                 assignment: [room.orderedDesks[0].id: anna,
                                              room.orderedDesks[1].id: ben])

        let document = DataFile(classes: [schoolClass], rooms: [room], charts: [chart])
        return (document, schoolClass, room, chart)
    }

    private func bundle(_ document: DataFile,
                        selection: BundleSelection? = nil,
                        photos: [UUID: BundlePhoto] = [:]) -> SeatingChartBundle {
        BundleTransfer.makeBundle(from: document,
                                  selection: selection ?? .everything(in: document),
                                  photos: photos)
    }

    // MARK: - Format

    @Test("A bundle survives a JSON round trip unchanged")
    func jsonRoundTrip() throws {
        let (document, _, _, _) = sampleDocument()
        let original = bundle(document)
        let decoded = try BundleCodec.decode(try BundleCodec.encode(original))

        #expect(decoded.classes == original.classes)
        #expect(decoded.rooms == original.rooms)
        #expect(decoded.rooms[0].seatNumbering == .frontRight)
        #expect(decoded.rooms[0].desks[2].isDisabled)
        #expect(decoded.charts.count == 1)
        #expect(decoded.charts[0].assignment == original.charts[0].assignment)
        #expect(decoded.charts[0].mode == .constrained(adjacency: .strict))
        #expect(abs(decoded.exportedAt.timeIntervalSince(original.exportedAt)) < 1.0)
    }

    @Test("Photo bytes survive the base64 round trip")
    func photoRoundTrip() throws {
        let (document, schoolClass, _, _) = sampleDocument()
        let anna = Fixture.id(schoolClass, "Anna")
        let bytes = Data((0..<512).map { UInt8($0 % 256) })
        let decoded = try BundleCodec.decode(
            try BundleCodec.encode(bundle(document, photos: [anna: BundlePhoto(studentID: anna, data: bytes)])))

        #expect(decoded.photos.count == 1)
        #expect(decoded.photos[0].data == bytes)
        #expect(decoded.classes[0].student(anna)?.photoFileName == "\(anna.uuidString).jpg")
    }

    @Test("A newer bundle version is refused rather than misread")
    func futureBundleVersionRefused() throws {
        let (document, _, _, _) = sampleDocument()
        var newer = bundle(document)
        newer.bundleSchemaVersion = 99
        let data = try BundleCodec.encode(newer)
        #expect(throws: BundleError.self) { try BundleCodec.decode(data) }
    }

    @Test("A newer data schema version is refused")
    func futureDataVersionRefused() throws {
        let (document, _, _, _) = sampleDocument()
        var newer = bundle(document)
        newer.dataSchemaVersion = 99
        let data = try BundleCodec.encode(newer)
        #expect(throws: BundleError.self) { try BundleCodec.decode(data) }
    }

    @Test("Foreign and malformed files are refused, not crashed on")
    func foreignFilesRefused() throws {
        // Valid JSON, wrong document.
        #expect(throws: BundleError.self) {
            try BundleCodec.decode(Data(#"{"hello":"world"}"#.utf8))
        }
        // Right shape, wrong magic string.
        let (document, _, _, _) = sampleDocument()
        var impostor = bundle(document)
        impostor.format = "com.example.something"
        let data = try BundleCodec.encode(impostor)
        #expect(throws: BundleError.self) { try BundleCodec.decode(data) }
        // Not JSON at all.
        #expect(throws: BundleError.self) {
            try BundleCodec.decode(Data([0xFF, 0xD8, 0x00, 0x01]))
        }
    }

    // MARK: - Export selection

    @Test("Charts are excluded when they are switched off, or their room is")
    func chartSelection() {
        let (document, schoolClass, room, _) = sampleDocument()

        var noCharts = BundleSelection.everything(in: document)
        noCharts.includeCharts = false
        #expect(bundle(document, selection: noCharts).charts.isEmpty)

        // Class selected, room not: the chart cannot come along.
        let classOnly = BundleSelection.onlyClass(schoolClass.id)
        #expect(bundle(document, selection: classOnly).charts.isEmpty)

        let roomOnly = BundleSelection.onlyRoom(room.id)
        #expect(bundle(document, selection: roomOnly).classes.isEmpty)
        #expect(bundle(document, selection: roomOnly).rooms.count == 1)
    }

    @Test("Switching photos off strips both the payload and the file names")
    func photoLessExport() {
        let (document, schoolClass, _, _) = sampleDocument()
        let anna = Fixture.id(schoolClass, "Anna")
        var selection = BundleSelection.everything(in: document)
        selection.includePhotos = false

        let result = bundle(document, selection: selection,
                            photos: [anna: BundlePhoto(studentID: anna, data: Data([1, 2, 3]))])
        #expect(result.photos.isEmpty)
        #expect(result.classes[0].students.allSatisfy { $0.photoFileName == nil },
                "a bundle must never name a photo it does not carry")
    }

    // MARK: - Add as copies

    @Test("Copies get entirely fresh ids")
    func copiesAreDisjoint() {
        let (document, _, _, _) = sampleDocument()
        let outcome = BundleTransfer.merge(bundle(document), into: document, mode: .addCopies)

        func ids(_ file: DataFile) -> (Set<UUID>, Set<UUID>, Set<UUID>, Set<UUID>, Set<UUID>) {
            (Set(file.classes.map(\.id)),
             Set(file.classes.flatMap { $0.students.map(\.id) }),
             Set(file.rooms.map(\.id)),
             Set(file.rooms.flatMap { $0.desks.map(\.id) }),
             Set(file.charts.map(\.id)))
        }
        let before = ids(document)
        var copied = outcome.document
        copied.classes.removeFirst(document.classes.count)
        copied.rooms.removeFirst(document.rooms.count)
        copied.charts.removeFirst(document.charts.count)
        let after = ids(copied)

        #expect(before.0.isDisjoint(with: after.0))
        #expect(before.1.isDisjoint(with: after.1))
        #expect(before.2.isDisjoint(with: after.2))
        #expect(before.3.isDisjoint(with: after.3))
        #expect(before.4.isDisjoint(with: after.4))
    }

    @Test("Copied constraints and charts still resolve inside the copy")
    func copiesKeepConstraints() {
        let (document, schoolClass, room, _) = sampleDocument()
        let outcome = BundleTransfer.merge(bundle(document), into: document, mode: .addCopies)

        let copiedClass = outcome.document.classes[1]
        let copiedRoom = outcome.document.rooms[1]
        #expect(copiedClass.constraints.count == schoolClass.constraints.count)

        let studentIDs = Set(copiedClass.students.map(\.id))
        let deskIDs = Set(copiedRoom.desks.map(\.id))
        for constraint in copiedClass.constraints {
            #expect(constraint.referencedStudents.allSatisfy(studentIDs.contains))
            if let deskID = constraint.referencedDesk {
                #expect(deskIDs.contains(deskID))
                #expect(constraint.referencedRoom == copiedRoom.id)
            }
        }

        // The copied pin lands on the same seat, because the grid copies verbatim.
        let originalPin = schoolClass.seatPins[0]
        let copiedPin = copiedClass.seatPins[0]
        #expect(room.seatNumber(of: originalPin.deskID) == copiedRoom.seatNumber(of: copiedPin.deskID))
        #expect(copiedRoom.seatNumbering == .frontRight)

        // The row pin is room-independent, so it must survive untouched.
        #expect(copiedClass.rowPins.map(\.row) == schoolClass.rowPins.map(\.row))

        let copiedChart = outcome.document.charts[1]
        #expect(copiedChart.classID == copiedClass.id)
        #expect(copiedChart.roomID == copiedRoom.id)
        #expect(copiedChart.assignment.count == 2)
        #expect(Set(copiedChart.assignment.keys).isSubset(of: deskIDs))
        #expect(Set(copiedChart.assignment.values).isSubset(of: studentIDs))
    }

    @Test("Copied keep-apart pairs stay canonical, so dedup keeps working")
    func copiesRecanonicaliseKeepApart() {
        let (document, _, _, _) = sampleDocument()
        let outcome = BundleTransfer.merge(bundle(document), into: document, mode: .addCopies)

        var copiedClass = outcome.document.classes[1]
        let pair = copiedClass.keepApartPairs[0]
        #expect(copiedClass.constraints.contains(Constraint.keepApartPair(pair.a, pair.b)))
        // Regression: remapping reorders uuidStrings, so a pair rebuilt without
        // re-canonicalising would slip past this dedup and duplicate itself.
        #expect(copiedClass.addKeepApart(pair.a, pair.b) == false)
        #expect(copiedClass.addKeepApart(pair.b, pair.a) == false)
    }

    @Test("Adding copies leaves everything already there untouched")
    func copiesDoNotDisturbExistingData() {
        let (document, _, _, _) = sampleDocument()
        let outcome = BundleTransfer.merge(bundle(document), into: document, mode: .addCopies)

        #expect(Array(outcome.document.classes.prefix(document.classes.count)) == document.classes)
        #expect(Array(outcome.document.rooms.prefix(document.rooms.count)) == document.rooms)
        #expect(Array(outcome.document.charts.prefix(document.charts.count)) == document.charts)
    }

    @Test("A class copied without its room loses only its fixed seats")
    func classWithoutItsRoom() {
        let (document, schoolClass, _, _) = sampleDocument()
        let classOnly = bundle(document, selection: .onlyClass(schoolClass.id))
        let outcome = BundleTransfer.merge(classOnly, into: DataFile(), mode: .addCopies)

        #expect(outcome.droppedSeatPins == 1)
        let copied = outcome.document.classes[0]
        #expect(copied.seatPins.isEmpty)
        #expect(copied.rowPins.count == 1, "row pins are room-independent")
        #expect(copied.keepApartPairs.count == 1)
        #expect(outcome.document.rooms.isEmpty)
        #expect(outcome.document.charts.isEmpty)
    }

    @Test("A room copied without its class arrives whole and unpinned")
    func roomWithoutItsClass() {
        let (document, _, room, _) = sampleDocument()
        let roomOnly = bundle(document, selection: .onlyRoom(room.id))
        let outcome = BundleTransfer.merge(roomOnly, into: DataFile(), mode: .addCopies)

        let copied = outcome.document.rooms[0]
        #expect(copied.desks.count == room.desks.count)
        #expect(Set(copied.desks.map(\.id)).isDisjoint(with: Set(room.desks.map(\.id))))
        #expect(copied.desks.map(\.gridX) == room.desks.map(\.gridX))
        #expect(copied.enabledDesks.count == room.enabledDesks.count)
        #expect(outcome.document.classes.isEmpty)
        #expect(outcome.droppedSeatPins == 0)
    }

    @Test("A colliding name gets a copy suffix; a free one is left alone")
    func nameCollisions() {
        #expect(BundleTransfer.uniqueName("5a", among: ["5b"]) == "5a")
        #expect(BundleTransfer.uniqueName("5a", among: ["5a"]) == L("transfer.copy_suffix", "5a"))
        #expect(BundleTransfer.uniqueName("5a", among: ["5a", L("transfer.copy_suffix", "5a")])
                == L("transfer.copy_suffix_n", "5a", 2))
    }

    @Test("Genders survive a copy, id remapping and all")
    func copiesKeepGenders() throws {
        var document = DataFile(classes: [Fixture.mixedClass(males: 2, females: 2, unspecified: 1)])
        let original = document.classes[0]
        let outcome = BundleTransfer.merge(bundle(document), into: document, mode: .addCopies)
        document = outcome.document

        let copy = try #require(document.classes.last)
        #expect(copy.id != original.id)
        // Matched by name: the ids are deliberately all different.
        for student in original.students {
            let copied = try #require(copy.students.first { $0.firstName == student.firstName })
            #expect(copied.gender == student.gender)
        }
        #expect(copy.students.count { $0.gender == .male } == 2)
        #expect(copy.students.count { $0.gender == .female } == 2)
    }

    @Test("Copies of photo-less students carry no file name")
    func copiesWithoutPhotos() {
        let (document, _, _, _) = sampleDocument()
        var selection = BundleSelection.everything(in: document)
        selection.includePhotos = false
        let outcome = BundleTransfer.merge(bundle(document, selection: selection),
                                           into: document, mode: .addCopies)
        #expect(outcome.document.classes[1].students.allSatisfy { $0.photoFileName == nil })
        #expect(outcome.photoWrites.isEmpty)
    }

    @Test("Copied photos are re-keyed to the new student ids")
    func copiedPhotosAreRekeyed() {
        let (document, schoolClass, _, _) = sampleDocument()
        let anna = Fixture.id(schoolClass, "Anna")
        let outcome = BundleTransfer.merge(
            bundle(document, photos: [anna: BundlePhoto(studentID: anna, data: Data([1, 2, 3]))]),
            into: document, mode: .addCopies)

        let copied = outcome.document.classes[1]
        let copiedAnna = copied.students.first { $0.firstName == "Anna" }!
        #expect(copiedAnna.id != anna)
        #expect(copiedAnna.photoFileName == "\(copiedAnna.id.uuidString).jpg")
        #expect(outcome.photoWrites == [PhotoWrite(studentID: copiedAnna.id,
                                                   fileExtension: "jpg", data: Data([1, 2, 3]))])
    }

    // MARK: - Replace matching

    @Test("Replacing overwrites by id in place and appends what is new")
    func replaceOverwritesInPlace() {
        let (document, schoolClass, _, _) = sampleDocument()
        var edited = schoolClass
        edited.name = "5a (edited)"
        edited.students.append(Student(firstName: "Dora"))
        let newcomer = Fixture.schoolClass(["Emil"], name: "6c")

        var incoming = bundle(document)
        incoming.classes = [edited, newcomer]

        let outcome = BundleTransfer.merge(incoming, into: document, mode: .replaceMatching)
        #expect(outcome.document.classes.count == 2)
        #expect(outcome.document.classes[0].id == schoolClass.id, "replaced in place")
        #expect(outcome.document.classes[0].name == "5a (edited)")
        #expect(outcome.document.classes[0].students.count == 4)
        #expect(outcome.document.classes[1].name == "6c")
    }

    @Test("Replacing keeps one chart per class and room pair")
    func replaceKeepsOneChartPerPair() {
        let (document, schoolClass, room, _) = sampleDocument()
        // Same pair, brand new chart id — matching on id alone would keep both.
        let regenerated = SeatingChart(classID: schoolClass.id, roomID: room.id,
                                       mode: .trueRandom,
                                       assignment: [room.orderedDesks[1].id: schoolClass.students[0].id])
        var incoming = bundle(document)
        incoming.charts = [regenerated]

        let outcome = BundleTransfer.merge(incoming, into: document, mode: .replaceMatching)
        #expect(outcome.document.charts.count == 1)
        #expect(outcome.document.charts[0].id == regenerated.id)
        #expect(outcome.document.charts[0].mode == .trueRandom)
    }

    @Test("Replacing reports students it dropped, so their photos can go too")
    func replaceReportsDroppedStudents() {
        let (document, schoolClass, _, _) = sampleDocument()
        let chiara = Fixture.id(schoolClass, "Chiara")
        var trimmed = schoolClass
        trimmed.students.removeAll { $0.id == chiara }
        var incoming = bundle(document)
        incoming.classes = [trimmed]

        let outcome = BundleTransfer.merge(incoming, into: document, mode: .replaceMatching)
        #expect(outcome.photoDeletions.contains(chiara))
        #expect(outcome.document.classes[0].students.count == 2)
    }

    @Test("A photo-less bundle does not blank photos that are already here")
    func replaceKeepsLocalPhotos() {
        var (document, schoolClass, _, _) = sampleDocument()
        let anna = Fixture.id(schoolClass, "Anna")
        document.classes[0].students[0].photoFileName = "\(anna.uuidString).png"

        var selection = BundleSelection.everything(in: document)
        selection.includePhotos = false
        let incoming = bundle(document, selection: selection)
        #expect(incoming.classes[0].students[0].photoFileName == nil)

        let outcome = BundleTransfer.merge(incoming, into: document, mode: .replaceMatching)
        #expect(outcome.document.classes[0].students[0].photoFileName == "\(anna.uuidString).png")
        #expect(outcome.photoDeletions.isEmpty)
    }

    @Test("Replacing re-binds fixed seats, because ids are preserved")
    func replaceKeepsSeatPins() {
        let (document, _, _, _) = sampleDocument()
        let outcome = BundleTransfer.merge(bundle(document), into: document, mode: .replaceMatching)
        #expect(outcome.document.classes.count == 1)
        #expect(outcome.document.classes[0].seatPins.count == 1)
        #expect(outcome.droppedSeatPins == 0)
    }

    // MARK: - Preview

    @Test("The preview counts what the merge actually does")
    func previewMatchesMerge() {
        let (document, schoolClass, _, _) = sampleDocument()
        let classOnly = bundle(document, selection: .onlyClass(schoolClass.id))

        let preview = BundleTransfer.preview(classOnly, against: DataFile(), mode: .addCopies)
        #expect(preview.classCount == 1)
        #expect(preview.roomCount == 0)
        #expect(preview.studentCount == 3)
        #expect(preview.droppedSeatPins == 1)
        #expect(preview.replacedClassCount == 0)

        let restore = BundleTransfer.preview(bundle(document), against: document,
                                             mode: .replaceMatching)
        #expect(restore.replacedClassCount == 1)
        #expect(restore.replacedRoomCount == 1)
        #expect(restore.droppedSeatPins == 0)
    }
}
