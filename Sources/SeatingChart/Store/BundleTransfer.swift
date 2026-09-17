import Foundation

/// One photo the caller has to write to disk after a merge.
struct PhotoWrite: Hashable {
    var studentID: UUID
    var fileExtension: String
    var data: Data
}

/// The result of merging a bundle into a document. Nothing here has touched the
/// file system — the caller replays `photoWrites` and `photoDeletions`.
struct MergeOutcome {
    var document: DataFile
    var photoWrites: [PhotoWrite] = []
    /// Students whose photo files are now orphaned and should be removed.
    var photoDeletions: [UUID] = []
    var importedClassIDs: [UUID] = []
    var importedRoomIDs: [UUID] = []
    /// Fixed seats that cannot survive the merge because their room is missing.
    var droppedSeatPins: Int = 0
}

/// What the import sheet shows before the user commits.
struct MergePreview: Hashable {
    var classCount: Int
    var roomCount: Int
    var studentCount: Int
    var photoCount: Int
    var chartCount: Int
    var replacedClassCount: Int
    var replacedRoomCount: Int
    var droppedSeatPins: Int
    var exportedAt: Date
}

/// Pure export/import logic over `DataFile`. No AppKit, no store, no I/O — all
/// of the id-remapping risk lives here, so it can be tested on its own.
enum BundleTransfer {

    // MARK: - Export

    /// `photos` is keyed by student id and gathered by the caller, which is the
    /// only side that can read the images folder.
    static func makeBundle(from document: DataFile,
                           selection: BundleSelection,
                           photos: [UUID: BundlePhoto],
                           exportedAt: Date = Date()) -> SeatingChartBundle {
        let classes = document.classes
            .filter { selection.classIDs.contains($0.id) }
            .map { schoolClass -> SchoolClass in
                var copy = schoolClass
                for index in copy.students.indices {
                    let student = copy.students[index]
                    if selection.includePhotos, let photo = photos[student.id] {
                        copy.students[index].photoFileName =
                            photoFileName(for: student.id, fileExtension: photo.fileExtension)
                    } else {
                        // Every photoFileName in a bundle has a matching photo.
                        copy.students[index].photoFileName = nil
                    }
                }
                return copy
            }

        let rooms = document.rooms.filter { selection.roomIDs.contains($0.id) }

        // Seat pins for rooms outside the selection are kept: re-importing into
        // the document they came from re-binds them. They are dropped, and
        // counted, only when ids are re-issued.
        let charts = selection.includeCharts
            ? document.charts.filter {
                selection.classIDs.contains($0.classID) && selection.roomIDs.contains($0.roomID)
            }
            : []

        let exportedStudentIDs = Set(classes.flatMap { $0.students.map(\.id) })
        let bundledPhotos = selection.includePhotos
            ? photos.values
                .filter { exportedStudentIDs.contains($0.studentID) }
                .sorted { $0.studentID.uuidString < $1.studentID.uuidString }
            : []

        return SeatingChartBundle(exportedAt: exportedAt,
                                  includesPhotos: selection.includePhotos,
                                  includesCharts: selection.includeCharts,
                                  classes: classes,
                                  rooms: rooms,
                                  charts: charts,
                                  photos: bundledPhotos)
    }

    // MARK: - Import

    static func merge(_ bundle: SeatingChartBundle,
                      into document: DataFile,
                      mode: ImportMode) -> MergeOutcome {
        switch mode {
        case .addCopies: addCopies(bundle, into: document)
        case .replaceMatching: replaceMatching(bundle, into: document)
        }
    }

    static func preview(_ bundle: SeatingChartBundle,
                        against document: DataFile,
                        mode: ImportMode) -> MergePreview {
        // Derived from the real merge so the sheet can never disagree with what
        // importing actually does.
        let outcome = merge(bundle, into: document, mode: mode)
        let existingClassIDs = Set(document.classes.map(\.id))
        let existingRoomIDs = Set(document.rooms.map(\.id))
        let replacedClasses = mode == .replaceMatching
            ? bundle.classes.filter { existingClassIDs.contains($0.id) }.count : 0
        let replacedRooms = mode == .replaceMatching
            ? bundle.rooms.filter { existingRoomIDs.contains($0.id) }.count : 0

        return MergePreview(classCount: bundle.classes.count,
                            roomCount: bundle.rooms.count,
                            studentCount: bundle.studentCount,
                            photoCount: bundle.photos.count,
                            chartCount: bundle.charts.count,
                            replacedClassCount: replacedClasses,
                            replacedRoomCount: replacedRooms,
                            droppedSeatPins: outcome.droppedSeatPins,
                            exportedAt: bundle.exportedAt)
    }

    // MARK: - Add as copies

    private static func addCopies(_ bundle: SeatingChartBundle,
                                  into document: DataFile) -> MergeOutcome {
        // Phase 1: every map first, so nothing is rewritten against a half-built
        // table. Desk ids are unique across the document, so one flat map does.
        var classMap: [UUID: UUID] = [:]
        var studentMap: [UUID: UUID] = [:]
        var roomMap: [UUID: UUID] = [:]
        var deskMap: [UUID: UUID] = [:]
        var chartMap: [UUID: UUID] = [:]

        for schoolClass in bundle.classes {
            classMap[schoolClass.id] = UUID()
            for student in schoolClass.students { studentMap[student.id] = UUID() }
        }
        for room in bundle.rooms {
            roomMap[room.id] = UUID()
            for desk in room.desks { deskMap[desk.id] = UUID() }
        }
        for chart in bundle.charts { chartMap[chart.id] = UUID() }

        let photosByStudent = photosByStudentID(bundle)
        var outcome = MergeOutcome(document: document)

        // Phase 2: rewrite, dropping any reference whose target is not mapped.
        var takenClassNames = document.classes.map(\.name)
        var newClasses: [SchoolClass] = []

        for schoolClass in bundle.classes {
            guard let newClassID = classMap[schoolClass.id] else { continue }

            var students: [Student] = []
            for student in schoolClass.students {
                guard let newStudentID = studentMap[student.id] else { continue }
                var photoFileName: String?
                // Keyed by the OLD id; the file name is rebuilt from the new one.
                if let photo = photosByStudent[student.id] {
                    let ext = Persistence.normalizedImageExtension(photo.fileExtension)
                    photoFileName = SeatingChartBundle.photoFileName(for: newStudentID,
                                                                     fileExtension: ext)
                    outcome.photoWrites.append(PhotoWrite(studentID: newStudentID,
                                                          fileExtension: ext,
                                                          data: photo.data))
                }
                students.append(Student(id: newStudentID,
                                        firstName: student.firstName,
                                        photoFileName: photoFileName,
                                        gender: student.gender))
            }

            var constraints: [Constraint] = []
            for constraint in schoolClass.constraints {
                switch constraint {
                case let .keepApart(a, b):
                    guard let a2 = studentMap[a], let b2 = studentMap[b] else { continue }
                    // Re-canonicalise: remapping changes the uuidString ordering
                    // that `keepApartPair` sorts on, and `addKeepApart`'s dedup
                    // relies on that canonical form.
                    constraints.append(Constraint.keepApartPair(a2, b2))
                case let .rowPin(student, row):
                    // Room-independent, so it survives a class-only export.
                    guard let student2 = studentMap[student] else { continue }
                    constraints.append(.rowPin(student: student2, row: row))
                case let .seatPin(student, roomID, deskID):
                    guard let student2 = studentMap[student],
                          let room2 = roomMap[roomID],
                          let desk2 = deskMap[deskID] else {
                        // The room did not come along. Never rebind to a local
                        // room with the same id — copies touch nothing existing.
                        outcome.droppedSeatPins += 1
                        continue
                    }
                    constraints.append(.seatPin(student: student2, roomID: room2, deskID: desk2))
                }
            }

            let name = uniqueName(schoolClass.name, among: takenClassNames)
            takenClassNames.append(name)
            newClasses.append(SchoolClass(id: newClassID, name: name,
                                          students: students, constraints: constraints))
            outcome.importedClassIDs.append(newClassID)
        }

        var takenRoomNames = document.rooms.map(\.name)
        var newRooms: [Room] = []
        for room in bundle.rooms {
            guard let newRoomID = roomMap[room.id] else { continue }
            let desks = room.desks.compactMap { desk -> Desk? in
                guard let newDeskID = deskMap[desk.id] else { return nil }
                return Desk(id: newDeskID, gridX: desk.gridX, gridY: desk.gridY,
                            isDisabled: desk.isDisabled)
            }
            let name = uniqueName(room.name, among: takenRoomNames)
            takenRoomNames.append(name)
            newRooms.append(Room(id: newRoomID, name: name, desks: desks,
                                 seatNumbering: room.seatNumbering))
            outcome.importedRoomIDs.append(newRoomID)
        }

        var newCharts: [SeatingChart] = []
        for chart in bundle.charts {
            guard let newChartID = chartMap[chart.id],
                  let classID = classMap[chart.classID],
                  let roomID = roomMap[chart.roomID] else { continue }
            var assignment: [UUID: UUID] = [:]
            for (deskID, studentID) in chart.assignment {
                guard let desk = deskMap[deskID], let student = studentMap[studentID] else { continue }
                assignment[desk] = student
            }
            newCharts.append(SeatingChart(id: newChartID, classID: classID, roomID: roomID,
                                          mode: chart.mode, assignment: assignment,
                                          generatedAt: chart.generatedAt))
        }

        // Phase 3: append only. Existing elements are never read or rewritten.
        outcome.document.classes.append(contentsOf: newClasses)
        outcome.document.rooms.append(contentsOf: newRooms)
        outcome.document.charts.append(contentsOf: newCharts)
        outcome.document.prune()
        return outcome
    }

    // MARK: - Replace matching

    private static func replaceMatching(_ bundle: SeatingChartBundle,
                                        into document: DataFile) -> MergeOutcome {
        let photosByStudent = photosByStudentID(bundle)
        var outcome = MergeOutcome(document: document)

        for incoming in bundle.classes {
            let existingIndex = outcome.document.classes.firstIndex { $0.id == incoming.id }
            let existing = existingIndex.map { outcome.document.classes[$0] }

            var merged = incoming
            for index in merged.students.indices {
                let student = merged.students[index]
                let localName = existing?.student(student.id)?.photoFileName
                if let photo = photosByStudent[student.id] {
                    let ext = Persistence.normalizedImageExtension(photo.fileExtension)
                    merged.students[index].photoFileName =
                        SeatingChartBundle.photoFileName(for: student.id, fileExtension: ext)
                    outcome.photoWrites.append(PhotoWrite(studentID: student.id,
                                                          fileExtension: ext,
                                                          data: photo.data))
                } else if !bundle.includesPhotos, let localName {
                    // A photo-less bundle is a partial backup: it must not blank
                    // avatars that are already on this Mac.
                    merged.students[index].photoFileName = localName
                } else {
                    merged.students[index].photoFileName = nil
                    if localName != nil { outcome.photoDeletions.append(student.id) }
                }
            }

            if let existing {
                // Students this class used to have and no longer does.
                let incomingIDs = Set(merged.students.map(\.id))
                outcome.photoDeletions.append(contentsOf:
                    existing.students.map(\.id).filter { !incomingIDs.contains($0) })
            }

            if let existingIndex {
                // In place, so the sidebar order does not jump around.
                outcome.document.classes[existingIndex] = merged
            } else {
                outcome.document.classes.append(merged)
            }
            outcome.importedClassIDs.append(merged.id)
        }

        for incoming in bundle.rooms {
            if let index = outcome.document.rooms.firstIndex(where: { $0.id == incoming.id }) {
                outcome.document.rooms[index] = incoming
            } else {
                outcome.document.rooms.append(incoming)
            }
            outcome.importedRoomIDs.append(incoming.id)
        }

        for incoming in bundle.charts {
            // Matching on id alone would break the one-chart-per-(class, room)
            // invariant the store relies on.
            outcome.document.charts.removeAll {
                $0.id == incoming.id || ($0.classID == incoming.classID && $0.roomID == incoming.roomID)
            }
            outcome.document.charts.append(incoming)
        }

        // Pins whose room is in neither the bundle nor the document: `prune()`
        // removes them, but the count has to be known before that.
        var desksByRoom: [UUID: Set<UUID>] = [:]
        for room in outcome.document.rooms { desksByRoom[room.id] = Set(room.desks.map(\.id)) }
        for schoolClass in bundle.classes {
            for pin in schoolClass.seatPins where !(desksByRoom[pin.roomID]?.contains(pin.deskID) ?? false) {
                outcome.droppedSeatPins += 1
            }
        }

        outcome.document.prune()
        return outcome
    }

    // MARK: - Helpers

    private static func photosByStudentID(_ bundle: SeatingChartBundle) -> [UUID: BundlePhoto] {
        Dictionary(bundle.photos.map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func photoFileName(for studentID: UUID, fileExtension: String) -> String {
        SeatingChartBundle.photoFileName(for: studentID, fileExtension: fileExtension)
    }

    /// Appends a "(copy)" suffix only on an exact collision.
    static func uniqueName(_ name: String, among existing: [String]) -> String {
        guard existing.contains(name) else { return name }
        var candidate = L("transfer.copy_suffix", name)
        var counter = 2
        while existing.contains(candidate) {
            candidate = L("transfer.copy_suffix_n", name, counter)
            counter += 1
        }
        return candidate
    }
}

extension SeatingChartBundle {
    /// The single place a photo file name is built, so it always matches what
    /// `Persistence` writes to disk.
    static func photoFileName(for studentID: UUID, fileExtension: String) -> String {
        "\(studentID.uuidString).\(Persistence.normalizedImageExtension(fileExtension))"
    }
}
