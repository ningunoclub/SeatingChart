import Foundation
import UniformTypeIdentifiers

/// One self-contained `.seatingchart` file: the selected classes and rooms,
/// optionally their generated charts, and the student photos inline.
///
/// Photos are base64 in the JSON (`JSONEncoder` encodes `Data` that way by
/// default), which keeps the whole export a single file that can be opened in a
/// text editor — the same trade the app already makes for `data.json`.
struct SeatingChartBundle: Codable, Hashable {
    static let currentVersion = 1
    static let formatIdentifier = "com.ningunosound.seatingchart"
    static let fileExtension = "seatingchart"

    /// Magic string, validated before anything else is trusted.
    var format: String
    /// Version of this container.
    var bundleSchemaVersion: Int
    /// `Persistence.schemaVersion` at export time, so the models can evolve
    /// independently of the container.
    var dataSchemaVersion: Int
    /// Informational only.
    var appVersion: String
    var exportedAt: Date
    var includesPhotos: Bool
    var includesCharts: Bool
    var classes: [SchoolClass]
    var rooms: [Room]
    var charts: [SeatingChart]
    var photos: [BundlePhoto]

    init(format: String = SeatingChartBundle.formatIdentifier,
         bundleSchemaVersion: Int = SeatingChartBundle.currentVersion,
         dataSchemaVersion: Int = Persistence.schemaVersion,
         appVersion: String = SeatingChartBundle.runningAppVersion,
         exportedAt: Date = Date(),
         includesPhotos: Bool = true,
         includesCharts: Bool = true,
         classes: [SchoolClass] = [],
         rooms: [Room] = [],
         charts: [SeatingChart] = [],
         photos: [BundlePhoto] = []) {
        self.format = format
        self.bundleSchemaVersion = bundleSchemaVersion
        self.dataSchemaVersion = dataSchemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.includesPhotos = includesPhotos
        self.includesCharts = includesCharts
        self.classes = classes
        self.rooms = rooms
        self.charts = charts
        self.photos = photos
    }

    static var runningAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// The registered type inside the packaged `.app`; a dynamic type bound to
    /// the extension under `swift run`, where there is no Info.plist at all.
    /// `UTType(exportedAs:)` is deliberately avoided — it traps when the
    /// identifier is not declared.
    static var contentType: UTType {
        UTType(tag: fileExtension, tagClass: .filenameExtension, conformingTo: .data) ?? .data
    }

    var studentCount: Int { classes.reduce(0) { $0 + $1.students.count } }
}

/// One student photo, keyed by student — never by file name. The name is
/// derived (`<uuid>.<ext>`) and has to be regenerated whenever ids are remapped.
struct BundlePhoto: Codable, Hashable {
    var studentID: UUID
    /// Always `jpg` for exports written by this version; honoured on import.
    var fileExtension: String
    var data: Data

    init(studentID: UUID, fileExtension: String = PhotoEncoder.fileExtension, data: Data) {
        self.studentID = studentID
        self.fileExtension = fileExtension
        self.data = data
    }
}

/// What the export sheet ticked.
struct BundleSelection: Hashable {
    var classIDs: Set<UUID>
    var roomIDs: Set<UUID>
    var includePhotos: Bool
    var includeCharts: Bool

    init(classIDs: Set<UUID> = [], roomIDs: Set<UUID> = [],
         includePhotos: Bool = true, includeCharts: Bool = true) {
        self.classIDs = classIDs
        self.roomIDs = roomIDs
        self.includePhotos = includePhotos
        self.includeCharts = includeCharts
    }

    var isEmpty: Bool { classIDs.isEmpty && roomIDs.isEmpty }

    static func everything(in document: DataFile) -> BundleSelection {
        BundleSelection(classIDs: Set(document.classes.map(\.id)),
                        roomIDs: Set(document.rooms.map(\.id)))
    }

    static func onlyClass(_ id: UUID) -> BundleSelection {
        BundleSelection(classIDs: [id], roomIDs: [])
    }

    static func onlyRoom(_ id: UUID) -> BundleSelection {
        BundleSelection(classIDs: [], roomIDs: [id])
    }
}

enum ImportMode: String, Codable, CaseIterable, Identifiable {
    /// Everything arrives with fresh ids; nothing already present is touched.
    case addCopies
    /// Same-id classes and rooms are overwritten — the backup-restore mode.
    case replaceMatching

    var id: String { rawValue }
}

enum BundleError: LocalizedError {
    case notASeatingChartFile
    case unsupportedBundleVersion(Int)
    case unsupportedDataVersion(Int)
    case fileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notASeatingChartFile:
            L("alert.bundle_import_failed.message")
        case .unsupportedBundleVersion, .unsupportedDataVersion:
            L("alert.bundle_too_new.message")
        case .fileTooLarge:
            L("alert.bundle_too_large.message")
        }
    }

    /// A file from a newer app gets its own alert title, so the user is told to
    /// update rather than told the file is broken.
    var isVersionMismatch: Bool {
        switch self {
        case .unsupportedBundleVersion, .unsupportedDataVersion: true
        case .notASeatingChartFile, .fileTooLarge: false
        }
    }
}

/// One shared codec so the export and import sides cannot drift apart.
enum BundleCodec {
    /// Refuse implausibly large files before handing them to `JSONDecoder`,
    /// which is not streaming and would block the main thread.
    static let maximumFileSize = 250 * 1024 * 1024

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ bundle: SeatingChartBundle) throws -> Data {
        try encoder.encode(bundle)
    }

    static func decode(_ data: Data) throws -> SeatingChartBundle {
        guard data.count <= maximumFileSize else { throw BundleError.fileTooLarge(data.count) }
        let bundle: SeatingChartBundle
        do {
            bundle = try decoder.decode(SeatingChartBundle.self, from: data)
        } catch {
            throw BundleError.notASeatingChartFile
        }
        guard bundle.format == SeatingChartBundle.formatIdentifier else {
            throw BundleError.notASeatingChartFile
        }
        // A newer file is refused outright rather than partially read.
        guard bundle.bundleSchemaVersion <= SeatingChartBundle.currentVersion else {
            throw BundleError.unsupportedBundleVersion(bundle.bundleSchemaVersion)
        }
        guard bundle.dataSchemaVersion <= Persistence.schemaVersion else {
            throw BundleError.unsupportedDataVersion(bundle.dataSchemaVersion)
        }
        return bundle
    }

    static func decode(contentsOf url: URL) throws -> SeatingChartBundle {
        // Check the size on disk first, so a huge file is never read into memory.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? Int, size > maximumFileSize {
            throw BundleError.fileTooLarge(size)
        }
        return try decode(try Data(contentsOf: url))
    }
}
