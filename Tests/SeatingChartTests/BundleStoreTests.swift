import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SeatingChart

/// The whole path: a real photo on disk, out to one file, and into a second
/// install that shares nothing with the first.
@Suite("Import & export end to end")
@MainActor
struct BundleStoreTests {

    private func makeRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SeatingChartBundle-\(UUID().uuidString)", isDirectory: true)
    }

    /// A real 1600×1200 PNG, so the export actually has something to shrink.
    private func writePNG(to url: URL) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: 1600, height: 1200,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        context.setFillColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 1)
        context.fillEllipse(in: CGRect(x: 400, y: 300, width: 800, height: 600))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test("A photo survives export into a second install, under its new id")
    func photoRoundTripsBetweenInstalls() throws {
        let sourceRoot = makeRoot()
        let targetRoot = makeRoot()
        let fileURL = makeRoot().appendingPathComponent("export.seatingchart")
        defer {
            for url in [sourceRoot, targetRoot, fileURL.deletingLastPathComponent()] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        // A class with a photographed student, and a room, in the first install.
        let sourceFiles = Persistence(rootDirectory: sourceRoot)
        try sourceFiles.ensureDirectories()
        let source = AppStore(persistence: sourceFiles)
        let classID = source.addClass()
        source.addStudents(names: "Anna\nBen", to: classID)
        source.addRoom()

        var schoolClass = try #require(source.schoolClass(classID))
        let anna = try #require(schoolClass.students.first { $0.firstName == "Anna" }).id
        let original = sourceRoot.appendingPathComponent("portrait.png")
        try writePNG(to: original)
        source.setPhoto(from: original, for: anna, in: classID)

        schoolClass = try #require(source.schoolClass(classID))
        #expect(schoolClass.student(anna)?.photoFileName == "\(anna.uuidString).png")

        source.exportBundle(selection: .everything(in: source.document), to: fileURL)
        #expect(source.alert == nil)
        let exportedSize = try Data(contentsOf: fileURL).count
        #expect(exportedSize > 0)
        // Shrunk to JPEG, so the file must be well under the raw PNG.
        let pngSize = try Data(contentsOf: sourceFiles.photoURL(named: "\(anna.uuidString).png")).count
        #expect(exportedSize < pngSize, "the export should shrink photos, not inflate them")

        // A second install that has never seen any of this.
        let targetFiles = Persistence(rootDirectory: targetRoot)
        try targetFiles.ensureDirectories()
        let target = AppStore(persistence: targetFiles)
        #expect(target.classes.isEmpty)

        let bundle = try #require(target.readBundle(at: fileURL))
        target.applyBundle(bundle, mode: .addCopies)
        #expect(target.alert == nil)

        #expect(target.classes.count == 1)
        #expect(target.rooms.count == 1)
        let imported = try #require(target.classes.first)
        let importedAnna = try #require(imported.students.first { $0.firstName == "Anna" })
        #expect(importedAnna.id != anna, "a copy gets a fresh id")

        // The photo landed under the NEW id and is a readable image.
        let name = try #require(importedAnna.photoFileName)
        #expect(name == "\(importedAnna.id.uuidString).jpg")
        let onDisk = targetFiles.photoURL(named: name)
        #expect(FileManager.default.fileExists(atPath: onDisk.path))
        let decoded = try #require(CGImageSourceCreateWithURL(onDisk as CFURL, nil))
        #expect(CGImageSourceGetCount(decoded) == 1)

        // The student without a photo stays without one.
        let importedBen = try #require(imported.students.first { $0.firstName == "Ben" })
        #expect(importedBen.photoFileName == nil)

        // And the source install is untouched by any of it.
        #expect(source.classes.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: sourceFiles.photoURL(named: "\(anna.uuidString).png").path))
    }

    @Test("A damaged file is refused with an alert, and changes nothing")
    func damagedFileIsRefused() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = Persistence(rootDirectory: root)
        try files.ensureDirectories()
        let store = AppStore(persistence: files)
        store.addClass()

        let garbage = root.appendingPathComponent("broken.seatingchart")
        try Data("not a seating chart at all".utf8).write(to: garbage)

        #expect(store.readBundle(at: garbage) == nil)
        #expect(store.alert?.title == L("alert.bundle_import_failed.title"))
        #expect(store.classes.count == 1, "a refused file must change nothing")
    }

    @Test("A file from a newer app says so, rather than claiming it is damaged")
    func newerFileNamesTheRealProblem() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = Persistence(rootDirectory: root)
        try files.ensureDirectories()
        let store = AppStore(persistence: files)

        var newer = BundleTransfer.makeBundle(from: DataFile(), selection: BundleSelection(),
                                              photos: [:])
        newer.bundleSchemaVersion = SeatingChartBundle.currentVersion + 1
        let url = root.appendingPathComponent("future.seatingchart")
        try BundleCodec.encode(newer).write(to: url)

        #expect(store.readBundle(at: url) == nil)
        #expect(store.alert?.title == L("alert.bundle_too_new.title"))
    }

    @Test("Re-importing a backup as a replace restores rather than duplicates")
    func replaceRestoresInPlace() throws {
        let root = makeRoot()
        let fileURL = root.appendingPathComponent("backup.seatingchart")
        defer { try? FileManager.default.removeItem(at: root) }

        let files = Persistence(rootDirectory: root)
        try files.ensureDirectories()
        let store = AppStore(persistence: files)
        let classID = store.addClass()
        store.addStudents(names: "Anna\nBen\nChiara", to: classID)
        store.addRoom()
        store.exportBundle(selection: .everything(in: store.document), to: fileURL)

        // Damage the live document, then restore from the file.
        store.deleteStudent(try #require(store.schoolClass(classID)).students[0].id, from: classID)
        #expect(store.schoolClass(classID)?.students.count == 2)

        let bundle = try #require(store.readBundle(at: fileURL))
        store.applyBundle(bundle, mode: .replaceMatching)

        #expect(store.classes.count == 1, "a replace must not duplicate the class")
        #expect(store.rooms.count == 1)
        #expect(store.schoolClass(classID)?.students.count == 3)
        // The snapshot taken before the overwrite is on disk.
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("data-backup-") }
        #expect(backups.count == 1)
    }
}
