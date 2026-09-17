import Foundation
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case schoolClass(UUID)
    case room(UUID)
    case chart
    case namePicker
    case grouping
    case timer
}

enum ModeKind: String, CaseIterable, Identifiable {
    case trueRandom
    case constrained

    var id: String { rawValue }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Which transfer sheet is showing. Kept on the store rather than in a view so
/// the menu, the sidebar and a Finder double-click all share one entry point —
/// and so a file opened before the window exists still gets presented.
enum TransferSheet: Identifiable {
    case export(BundleSelection)
    case importSummary(PendingImport)

    var id: String {
        switch self {
        case .export: "export"
        case let .importSummary(pending): pending.id.uuidString
        }
    }
}

/// A file that has been read and validated, waiting for the user to choose how
/// to merge it.
struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
    let bundle: SeatingChartBundle
}

/// Root store: owns the document, performs CRUD, and autosaves.
@Observable
final class AppStore {
    var classes: [SchoolClass] = []
    var rooms: [Room] = []
    var charts: [SeatingChart] = []

    // Session-only UI state.
    var sidebarSelection: SidebarItem?
    var chartClassID: UUID?
    var chartRoomID: UUID?
    var modeKind: ModeKind = .constrained
    var adjacencyMode: AdjacencyMode = .relaxed
    var alert: AppAlert?

    /// Name picker state. Its own object so the picker's class selection and
    /// draw round stay independent of the seating chart.
    let namePicker = NamePickerModel()

    /// Auto-grouping state, shared by the grouping tab and its overlay. Its own
    /// class selection too, for the same reason the name picker has one.
    let grouping = GroupingModel()

    /// Countdown timer state, shared by the timer tab and its overlay.
    let timer = TimerModel()

    @ObservationIgnored private let persistence: Persistence
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private var isLoading = false

    init(persistence: Persistence = Persistence()) {
        self.persistence = persistence
        load()
    }

    var imagesDirectory: URL { persistence.imagesDirectory }

    func photoURL(named name: String) -> URL { persistence.photoURL(named: name) }

    // MARK: - Loading & saving

    private func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            let document = try persistence.load()
            classes = document.classes
            rooms = document.rooms
            charts = document.charts
        } catch {
            alert = AppAlert(title: L("alert.load_failed.title"),
                             message: error.localizedDescription)
        }
        chartClassID = classes.first?.id
        chartRoomID = rooms.first?.id
        namePicker.classID = classes.first?.id
        grouping.classID = classes.first?.id
        sidebarSelection = .chart
    }

    /// Debounced autosave; every mutation funnels through here.
    func scheduleSave() {
        guard !isLoading else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let document = DataFile(classes: classes, rooms: rooms, charts: charts)
        do {
            try persistence.save(document)
        } catch {
            alert = AppAlert(title: L("alert.save_failed.title"),
                             message: error.localizedDescription)
        }
    }

    // MARK: - Classes

    func schoolClass(_ id: UUID?) -> SchoolClass? {
        guard let id else { return nil }
        return classes.first { $0.id == id }
    }

    @discardableResult
    func addClass() -> UUID {
        let new = SchoolClass(name: L("class.new_name"))
        classes.append(new)
        chartClassID = chartClassID ?? new.id
        scheduleSave()
        return new.id
    }

    func update(_ schoolClass: SchoolClass) {
        guard let index = classes.firstIndex(where: { $0.id == schoolClass.id }) else { return }
        guard classes[index] != schoolClass else { return }
        classes[index] = schoolClass
        scheduleSave()
    }

    func deleteClass(_ id: UUID) {
        guard let index = classes.firstIndex(where: { $0.id == id }) else { return }
        for student in classes[index].students { persistence.deleteAllPhotos(for: student.id) }
        classes.remove(at: index)
        charts.removeAll { $0.classID == id }
        if chartClassID == id { chartClassID = classes.first?.id }
        if namePicker.classID == id { namePicker.classID = classes.first?.id }
        if grouping.classID == id { grouping.classID = classes.first?.id }
        if sidebarSelection == .schoolClass(id) { sidebarSelection = .chart }
        scheduleSave()
    }

    func binding(forClass id: UUID) -> Binding<SchoolClass> {
        Binding(
            get: { [weak self] in self?.schoolClass(id) ?? SchoolClass(id: id, name: "") },
            set: { [weak self] newValue in self?.update(newValue) }
        )
    }

    // MARK: - Students

    /// Adds one student per non-empty line.
    func addStudents(names: String, to classID: UUID) {
        guard var target = schoolClass(classID) else { return }
        let parsed = names
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parsed.isEmpty else { return }
        target.students.append(contentsOf: parsed.map { Student(firstName: $0) })
        update(target)
    }

    func deleteStudent(_ studentID: UUID, from classID: UUID) {
        guard var target = schoolClass(classID) else { return }
        persistence.deleteAllPhotos(for: studentID)
        target.students.removeAll { $0.id == studentID }
        target.pruneDanglingConstraints()
        update(target)
        // The student may have been seated in a stored chart.
        for index in charts.indices where charts[index].classID == classID {
            charts[index].assignment = charts[index].assignment.filter { $0.value != studentID }
        }
        scheduleSave()
    }

    func setPhoto(from source: URL, for studentID: UUID, in classID: UUID) {
        guard var target = schoolClass(classID),
              let index = target.students.firstIndex(where: { $0.id == studentID }) else { return }
        do {
            let name = try persistence.importPhoto(from: source, for: studentID)
            target.students[index].photoFileName = name
            update(target)
        } catch {
            alert = AppAlert(title: L("alert.photo_failed.title"),
                             message: error.localizedDescription)
        }
    }

    func removePhoto(for studentID: UUID, in classID: UUID) {
        guard var target = schoolClass(classID),
              let index = target.students.firstIndex(where: { $0.id == studentID }) else { return }
        persistence.deleteAllPhotos(for: studentID)
        target.students[index].photoFileName = nil
        update(target)
    }

    // MARK: - Rooms

    func room(_ id: UUID?) -> Room? {
        guard let id else { return nil }
        return rooms.first { $0.id == id }
    }

    @discardableResult
    func addRoom() -> UUID {
        var new = Room(name: L("room.new_name"))
        new.desks = Room.regularLayout(rows: 4, seatsPerRow: 6, aisleAfterSeat: 3)
        rooms.append(new)
        chartRoomID = chartRoomID ?? new.id
        scheduleSave()
        return new.id
    }

    func update(_ room: Room) {
        guard let index = rooms.firstIndex(where: { $0.id == room.id }) else { return }
        guard rooms[index] != room else { return }
        let removedDesks = Set(rooms[index].desks.map(\.id)).subtracting(room.desks.map(\.id))
        rooms[index] = room
        if !removedDesks.isEmpty {
            // Prune seat pins and chart seats that referenced deleted desks.
            for classIndex in classes.indices {
                classes[classIndex].constraints.removeAll { constraint in
                    guard let desk = constraint.referencedDesk,
                          constraint.referencedRoom == room.id else { return false }
                    return removedDesks.contains(desk)
                }
            }
            for chartIndex in charts.indices where charts[chartIndex].roomID == room.id {
                charts[chartIndex].assignment = charts[chartIndex].assignment
                    .filter { !removedDesks.contains($0.key) }
            }
        }
        scheduleSave()
    }

    func deleteRoom(_ id: UUID) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        rooms.remove(at: index)
        charts.removeAll { $0.roomID == id }
        for classIndex in classes.indices {
            classes[classIndex].constraints.removeAll { $0.referencedRoom == id }
        }
        if chartRoomID == id { chartRoomID = rooms.first?.id }
        if sidebarSelection == .room(id) { sidebarSelection = .chart }
        scheduleSave()
    }

    func binding(forRoom id: UUID) -> Binding<Room> {
        Binding(
            get: { [weak self] in self?.room(id) ?? Room(id: id, name: "") },
            set: { [weak self] newValue in self?.update(newValue) }
        )
    }

    // MARK: - Charts

    var generationMode: GenerationMode {
        switch modeKind {
        case .trueRandom: .trueRandom
        case .constrained: .constrained(adjacency: adjacencyMode)
        }
    }

    func chart(classID: UUID?, roomID: UUID?) -> SeatingChart? {
        guard let classID, let roomID else { return nil }
        return charts.first { $0.classID == classID && $0.roomID == roomID }
    }

    var currentChart: SeatingChart? { chart(classID: chartClassID, roomID: chartRoomID) }
    var currentClass: SchoolClass? { schoolClass(chartClassID) }
    var currentRoom: Room? { room(chartRoomID) }

    var canGenerate: Bool {
        guard let schoolClass = currentClass, let room = currentRoom else { return false }
        return !schoolClass.students.isEmpty && !room.enabledDesks.isEmpty
    }

    func generate() {
        guard let schoolClass = currentClass, let room = currentRoom else { return }
        do {
            let chart = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                                      mode: generationMode)
            store(chart)
        } catch let error as GeneratorError {
            alert = AppAlert(title: L("alert.generate_failed.title"),
                             message: error.message(in: schoolClass, room: room))
        } catch {
            alert = AppAlert(title: L("alert.generate_failed.title"),
                             message: error.localizedDescription)
        }
    }

    private func store(_ chart: SeatingChart) {
        if let index = charts.firstIndex(where: {
            $0.classID == chart.classID && $0.roomID == chart.roomID
        }) {
            charts[index] = chart
        } else {
            charts.append(chart)
        }
        scheduleSave()
    }

    // MARK: - Name picker

    var pickerClass: SchoolClass? { schoolClass(namePicker.classID) }

    var canPickName: Bool {
        guard let students = pickerClass?.students else { return false }
        return !students.isEmpty && !namePicker.isShuffling
    }

    func pickName() {
        guard let students = pickerClass?.students, !students.isEmpty else { return }
        namePicker.pick(from: students)
    }

    // MARK: - Grouping

    var groupingClass: SchoolClass? { schoolClass(grouping.classID) }

    var canMakeGroups: Bool {
        guard let students = groupingClass?.students else { return false }
        return !students.isEmpty
    }

    func makeGroups() {
        guard let students = groupingClass?.students, !students.isEmpty else { return }
        grouping.make(from: students)
    }

    // MARK: - Timer

    func setTimerImage(from source: URL) {
        do {
            timer.doneImageFileName = try persistence.importTimerImage(from: source)
        } catch {
            alert = AppAlert(title: L("alert.timer_image_failed.title"),
                             message: error.localizedDescription)
        }
    }

    func removeTimerImage() {
        persistence.deleteTimerImages()
        timer.doneImageFileName = nil
    }

    // MARK: - Import & export

    /// The document as it stands right now.
    var document: DataFile { DataFile(classes: classes, rooms: rooms, charts: charts) }

    var transferSheet: TransferSheet?

    /// Gathers and shrinks the photos, then writes one self-contained file.
    func exportBundle(selection: BundleSelection, to url: URL) {
        var photos: [UUID: BundlePhoto] = [:]
        if selection.includePhotos {
            for schoolClass in classes where selection.classIDs.contains(schoolClass.id) {
                for student in schoolClass.students {
                    // A missing or unreadable file reads as "no photo", so one
                    // bad portrait cannot fail the whole export.
                    guard let name = student.photoFileName,
                          let data = PhotoEncoder.jpegData(contentsOf: persistence.photoURL(named: name))
                    else { continue }
                    photos[student.id] = BundlePhoto(studentID: student.id, data: data)
                }
            }
        }
        do {
            let bundle = BundleTransfer.makeBundle(from: document, selection: selection, photos: photos)
            try BundleCodec.encode(bundle).write(to: url, options: .atomic)
        } catch {
            alert = AppAlert(title: L("alert.bundle_export_failed.title"),
                             message: error.localizedDescription)
        }
    }

    /// Reads and validates a file. Returns `nil` after posting an alert.
    func readBundle(at url: URL) -> SeatingChartBundle? {
        do {
            return try BundleCodec.decode(contentsOf: url)
        } catch {
            // A file from a newer app is told apart from a broken one, so the
            // user is asked to update rather than to find another copy.
            let isNewer = (error as? BundleError)?.isVersionMismatch ?? false
            alert = AppAlert(title: isNewer ? L("alert.bundle_too_new.title")
                                            : L("alert.bundle_import_failed.title"),
                             message: error.localizedDescription)
            return nil
        }
    }

    func applyBundle(_ bundle: SeatingChartBundle, mode: ImportMode) {
        let outcome = BundleTransfer.merge(bundle, into: document, mode: mode)

        // There is no undo anywhere in this app, so snapshot before anything is
        // overwritten. Flush first: the backup has to capture what is on screen
        // now, not whatever the debounced autosave last happened to write.
        saveNow()
        _ = try? persistence.backupDataFile()

        for studentID in outcome.photoDeletions { persistence.deleteAllPhotos(for: studentID) }

        var failedPhotos = 0
        for write in outcome.photoWrites {
            do {
                try persistence.writePhoto(write.data, fileExtension: write.fileExtension,
                                           for: write.studentID)
            } catch {
                // Carry on: a student without a photo falls back to initials,
                // whereas aborting here would leave the import half-applied.
                failedPhotos += 1
            }
        }

        classes = outcome.document.classes
        rooms = outcome.document.rooms
        charts = outcome.document.charts
        // Photo files were just replaced under paths the cache may already hold.
        PhotoCache.invalidate()
        // Far too much to leave sitting in the one-second autosave window.
        saveNow()

        if schoolClass(chartClassID) == nil { chartClassID = classes.first?.id }
        if room(chartRoomID) == nil { chartRoomID = rooms.first?.id }
        if schoolClass(namePicker.classID) == nil { namePicker.classID = classes.first?.id }
        if schoolClass(grouping.classID) == nil { grouping.classID = classes.first?.id }

        // Land on what just arrived, so the import is visibly there.
        if let classID = outcome.importedClassIDs.first {
            sidebarSelection = .schoolClass(classID)
        } else if let roomID = outcome.importedRoomIDs.first {
            sidebarSelection = .room(roomID)
        }

        if failedPhotos > 0 {
            alert = AppAlert(title: L("alert.photo_failed.title"),
                             message: L("alert.bundle_photos_failed.message", failedPhotos))
        }
    }

    // MARK: - Seat pins from the chart view

    func pinStudent(_ studentID: UUID, toDesk deskID: UUID) {
        guard let classID = chartClassID, let roomID = chartRoomID,
              var target = schoolClass(classID) else { return }
        target.setSeatPin(student: studentID, roomID: roomID, deskID: deskID)
        update(target)
    }

    func removeSeatPin(deskID: UUID) {
        guard let classID = chartClassID, let roomID = chartRoomID,
              var target = schoolClass(classID) else { return }
        target.removeSeatPin(roomID: roomID, deskID: deskID)
        update(target)
    }

    func seatPinnedStudent(atDesk deskID: UUID) -> UUID? {
        guard let roomID = chartRoomID, let target = currentClass else { return nil }
        return target.seatPins(inRoom: roomID).first { $0.deskID == deskID }?.student
    }
}

extension AppStore {
    /// The instance used by the app (the delegate and the presentation window
    /// need to reach it outside the SwiftUI environment).
    static let shared = AppStore()
}
