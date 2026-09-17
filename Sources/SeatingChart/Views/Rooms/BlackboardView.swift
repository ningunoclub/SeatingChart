import SwiftUI

/// The fixed orientation reference: always drawn across the top of a room.
struct BlackboardView: View {
    var width: CGFloat?
    var height: CGFloat = 26
    var onDark: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(onDark ? Color.white.opacity(0.14) : Theme.blackboardColor)
            .frame(width: width, height: height)
            .overlay {
                Text(L("room.blackboard"))
                    .font(.system(size: min(height * 0.5, 13), weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(onDark ? Color.white.opacity(0.75) : Color.white.opacity(0.9))
            }
            .accessibilityLabel(L("room.blackboard"))
    }
}
