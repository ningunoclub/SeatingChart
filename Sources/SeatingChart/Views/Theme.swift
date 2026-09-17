import SwiftUI

enum Theme {
    /// Avatar colours, picked deterministically from the student id.
    static let avatarColors: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.75),
        Color(red: 0.85, green: 0.42, blue: 0.24),
        Color(red: 0.27, green: 0.60, blue: 0.42),
        Color(red: 0.62, green: 0.33, blue: 0.66),
        Color(red: 0.83, green: 0.60, blue: 0.16),
        Color(red: 0.72, green: 0.28, blue: 0.40),
        Color(red: 0.27, green: 0.54, blue: 0.62),
        Color(red: 0.45, green: 0.45, blue: 0.72),
    ]

    static func avatarColor(for student: Student) -> Color {
        avatarColors[student.colorIndex(buckets: avatarColors.count)]
    }

    static let deskCorner: CGFloat = 8
    static let blackboardColor = Color(red: 0.16, green: 0.20, blue: 0.18)
}

/// Small main-thread cache so scrolling a class list does not re-read files.
enum PhotoCache {
    private static var images: [String: NSImage] = [:]

    static func image(at url: URL) -> NSImage? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(modified)"
        if let cached = images[key] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[key] = image
        return image
    }

    /// Dropped wholesale after an import replaces photo files. Coarse on
    /// purpose: importing is rare, and re-reading a class list costs nothing
    /// next to serving a stale portrait.
    static func invalidate() {
        images.removeAll()
    }
}
