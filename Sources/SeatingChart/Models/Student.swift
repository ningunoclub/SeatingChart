import Foundation

/// Male, female, or left alone. Only the auto-grouping reads this — seating,
/// the name picker and the avatars stay gender-blind.
enum Gender: String, Codable, CaseIterable, Identifiable {
    case unspecified
    case male
    case female

    var id: String { rawValue }
}

/// A single pupil. Only a first name is kept — see build-plan §9.
struct Student: Codable, Identifiable, Hashable {
    var id: UUID
    var firstName: String
    /// File name inside `Images/`; `nil` means the initials avatar is shown.
    var photoFileName: String?
    var gender: Gender

    init(id: UUID = UUID(), firstName: String, photoFileName: String? = nil,
         gender: Gender = .unspecified) {
        self.id = id
        self.firstName = firstName
        self.photoFileName = photoFileName
        self.gender = gender
    }

    /// Hand-written because `gender` arrived after the first release: a default
    /// value does not make the synthesized decoder tolerate a missing key, and
    /// every `data.json` and `.seatingchart` written before it lacks one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        firstName = try container.decode(String.self, forKey: .firstName)
        photoFileName = try container.decodeIfPresent(String.self, forKey: .photoFileName)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender) ?? .unspecified
    }

    /// One or two letters for the fallback avatar.
    var initials: String {
        let parts = firstName.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = parts.prefix(2).compactMap(\.first)
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }

    /// Stable bucket derived from the id, used to pick an avatar colour.
    func colorIndex(buckets: Int) -> Int {
        var hash: UInt64 = 5381
        for byte in withUnsafeBytes(of: id.uuid, Array.init) {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % UInt64(max(1, buckets)))
    }
}
