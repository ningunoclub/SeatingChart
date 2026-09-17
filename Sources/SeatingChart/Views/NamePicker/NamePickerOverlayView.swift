import SwiftUI

/// What the class sees. Display only — every control lives in the app window.
/// Type scales with the frame, the way `ChartDeskView` scales to its height, so
/// the same view works as a 220pt overlay and as the in-app preview.
struct NamePickerOverlayView: View {
    var cornerRadius: CGFloat = 16
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.92))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                content(in: proxy.size)
                    .padding(.horizontal, proxy.size.width * 0.07)
                    .padding(.vertical, proxy.size.height * 0.09)
                    // One settle at the end of the draw, rather than a
                    // transition on every 55ms flicker.
                    .scaleEffect(store.namePicker.isShuffling ? 0.94 : 1)
                    .opacity(store.namePicker.isShuffling ? 0.7 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7),
                               value: store.namePicker.isShuffling)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let student = displayedStudent {
            switch store.namePicker.displayMode {
            case .name:
                name(student, size: size.height * 0.34)
            case .photo:
                AvatarView(student: student, size: min(size.width, size.height) * 0.74)
            case .both:
                VStack(spacing: size.height * 0.05) {
                    AvatarView(student: student, size: min(size.width, size.height) * 0.46)
                    name(student, size: size.height * 0.18)
                }
            }
        } else {
            Text(L("picker.waiting"))
                .font(.system(size: max(11, size.height * 0.09), weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func name(_ student: Student, size: CGFloat) -> some View {
        Text(student.firstName)
            .font(.system(size: max(11, size), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }

    private var displayedStudent: Student? {
        guard let id = store.namePicker.displayedStudentID else { return nil }
        return store.pickerClass?.student(id)
    }
}
