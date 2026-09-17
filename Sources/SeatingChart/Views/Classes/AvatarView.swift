import SwiftUI

/// Photo if there is one, otherwise a coloured initials circle.
struct AvatarView: View {
    let student: Student
    var size: CGFloat = 28
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let name = student.photoFileName,
               let image = PhotoCache.image(at: store.photoURL(named: name)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.avatarColor(for: student)
                    .overlay {
                        Text(student.initials)
                            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .padding(2)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(student.firstName)
    }
}
