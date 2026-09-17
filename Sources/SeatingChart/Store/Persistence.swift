import Foundation

/// The whole document. `schemaVersion` exists from day one for future migrations.
struct DataFile: Codable, Hashable {
    var schemaVersion: Int
    var classes: [SchoolClass]
    var rooms: [Room]
    var charts: [SeatingChart]

    init(schemaVersion: Int = Persistence.schemaVersion,
         classes: [SchoolClass] = [], rooms: [Room] = [], charts: [SeatingChart] = []) {
        self.schemaVersion = schemaVersion
        self.classes = classes
        self.rooms = rooms
        self.charts = charts
    }
}

enum PersistenceError: Error {
    case unsupportedSchema(Int)
    case unreadableImage(URL)
}

/// JSON document plus an images folder under Application Support.
struct Persistence {
    static let schemaVersion = 1
    static let allowedImageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "bmp"]

    let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.rootDirectory = base.appendingPathComponent("SeatingChart", isDirectory: true)
        }
    }

    var dataFileURL: URL { rootDirectory.appendingPathComponent("data.json") }
    var imagesDirectory: URL { rootDirectory.appendingPathComponent("Images", isDirectory: true) }

    func photoURL(named name: String) -> URL { imagesDirectory.appendingPathComponent(name) }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Document

    func load() throws -> DataFile {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return DataFile() }
        let data = try Data(contentsOf: dataFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var document = try decoder.decode(DataFile.self, from: data)
        guard document.schemaVersion <= Persistence.schemaVersion else {
            throw PersistenceError.unsupportedSchema(document.schemaVersion)
        }
        document.prune()
        return document
    }

    func save(_ document: DataFile) throws {
        try ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var copy = document
        copy.schemaVersion = Persistence.schemaVersion
        let data = try encoder.encode(copy)
        // Atomic so a crash mid-write never leaves a truncated file.
        try data.write(to: dataFileURL, options: .atomic)
    }

    /// Snapshots `data.json` beside itself before a destructive import. The app
    /// has no undo, so this is the only way back from a replace.
    @discardableResult
    func backupDataFile() throws -> URL? {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return nil }
        let stamp = DateFormatter.backupStamp.string(from: Date())
        let destination = rootDirectory.appendingPathComponent("data-backup-\(stamp).json")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: dataFileURL, to: destination)
        return destination
    }

    // MARK: - Photos

    /// The one place an image extension is normalised, so a stored file name and
    /// a `Student.photoFileName` can never disagree.
    static func normalizedImageExtension(_ fileExtension: String) -> String {
        let lowered = fileExtension.lowercased()
        return allowedImageExtensions.contains(lowered) ? lowered : "png"
    }

    /// Copies a picked image into `Images/` named by student id, replacing any
    /// previous photo for that student. Returns the stored file name.
    @discardableResult
    func importPhoto(from source: URL, for studentID: UUID) throws -> String {
        try writePhoto(try Data(contentsOf: source),
                       fileExtension: source.pathExtension,
                       for: studentID)
    }

    /// Writes photo bytes into `Images/` named by student id, replacing any
    /// previous photo for that student. Returns the stored file name.
    ///
    /// Deliberately not a temp file plus `copyItem`: that preserves the source
    /// modification date, and `PhotoCache` keys on path plus mtime.
    @discardableResult
    func writePhoto(_ data: Data, fileExtension: String, for studentID: UUID) throws -> String {
        try ensureDirectories()
        let name = "\(studentID.uuidString).\(Persistence.normalizedImageExtension(fileExtension))"
        deleteAllPhotos(for: studentID)
        try data.write(to: photoURL(named: name), options: .atomic)
        return name
    }

    func deletePhoto(named name: String) {
        try? FileManager.default.removeItem(at: photoURL(named: name))
    }

    /// The timer's "all done" picture shares the `Images/` folder. A fixed base
    /// name cannot collide with the student photos, which are named by UUID.
    private static let timerImageBaseName = "timer-done"

    @discardableResult
    func importTimerImage(from source: URL) throws -> String {
        try ensureDirectories()
        let ext = source.pathExtension.lowercased()
        let suffix = Persistence.allowedImageExtensions.contains(ext) ? ext : "png"
        let name = "\(Persistence.timerImageBaseName).\(suffix)"
        // `copyItem` throws onto an existing file, so clear the way first.
        deleteTimerImages()
        try FileManager.default.copyItem(at: source, to: photoURL(named: name))
        return name
    }

    /// Removes every extension variant of the timer picture.
    func deleteTimerImages() {
        for ext in Persistence.allowedImageExtensions {
            let url = photoURL(named: "\(Persistence.timerImageBaseName).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Removes every extension variant belonging to a student.
    func deleteAllPhotos(for studentID: UUID) {
        for ext in Persistence.allowedImageExtensions {
            let url = photoURL(named: "\(studentID.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

extension DataFile {
    /// Drops constraints and charts pointing at deleted classes, rooms, desks or students.
    mutating func prune() {
        let roomIDs = Set(rooms.map(\.id))
        let classIDs = Set(classes.map(\.id))
        var desksByRoom: [UUID: Set<UUID>] = [:]
        for room in rooms { desksByRoom[room.id] = Set(room.desks.map(\.id)) }

        for index in classes.indices {
            classes[index].pruneDanglingConstraints()
            classes[index].constraints.removeAll { constraint in
                guard case let .seatPin(_, roomID, deskID) = constraint else { return false }
                guard let desks = desksByRoom[roomID] else { return true }
                return !desks.contains(deskID)
            }
        }

        charts.removeAll { chart in
            guard classIDs.contains(chart.classID), roomIDs.contains(chart.roomID) else { return true }
            return false
        }
        // Drop stale seat assignments inside surviving charts.
        for index in charts.indices {
            let chart = charts[index]
            let validDesks = desksByRoom[chart.roomID] ?? []
            let validStudents = Set(classes.first { $0.id == chart.classID }?.students.map(\.id) ?? [])
            charts[index].assignment = chart.assignment.filter {
                validDesks.contains($0.key) && validStudents.contains($0.value)
            }
        }
    }
}

private extension DateFormatter {
    /// An explicit pattern rather than ISO8601: colons are legal in file names
    /// but Finder renders them as slashes.
    static let backupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
