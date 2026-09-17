import SwiftUI

enum DeskCardStyle {
    /// Normal in-app appearance.
    case screen
    /// Black background, large type — for the beamer.
    case presentation
    /// White background, black text — for PDF and print.
    case print

    var textColor: Color {
        switch self {
        case .screen: .primary
        case .presentation: .white
        case .print: .black
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .screen: .secondary
        case .presentation: Color.white.opacity(0.55)
        case .print: Color.black.opacity(0.45)
        }
    }

    var fill: Color {
        switch self {
        case .screen: Color(nsColor: .controlBackgroundColor)
        case .presentation: Color.white.opacity(0.10)
        case .print: .white
        }
    }

    var stroke: Color {
        switch self {
        case .screen: Color.secondary.opacity(0.30)
        case .presentation: Color.white.opacity(0.22)
        case .print: Color.black.opacity(0.35)
        }
    }
}

/// One desk in a generated chart: photo (or initials), first name, seat number.
struct ChartDeskView: View {
    let desk: Desk
    let student: Student?
    let seatNumber: Int
    var isPinned = false
    var style: DeskCardStyle = .screen
    var height: CGFloat = 72

    private var isEmptySeat: Bool { student == nil && !desk.isDisabled }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.deskCorner)
                .fill(desk.isDisabled ? Color.gray.opacity(0.10) : style.fill)
            RoundedRectangle(cornerRadius: Theme.deskCorner)
                .strokeBorder(style.stroke, lineWidth: desk.isDisabled ? 0.5 : 1)
            if desk.isDisabled { HatchPattern() }

            if let student {
                seated(student)
            } else {
                Text("\(seatNumber)")
                    .font(.system(size: height * 0.24, weight: .medium, design: .rounded))
                    .foregroundStyle(desk.isDisabled ? style.secondaryTextColor.opacity(0.6)
                                                     : style.secondaryTextColor)
            }
        }
        .opacity(desk.isDisabled ? 0.65 : 1)
        .accessibilityLabel(accessibilityText)
    }

    private func seated(_ student: Student) -> some View {
        VStack(spacing: height * 0.045) {
            AvatarView(student: student, size: height * 0.44)
            Text(student.firstName)
                .font(.system(size: height * 0.20, weight: .medium))
                .foregroundStyle(style.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 5)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: height * 0.13))
                        .foregroundStyle(style.secondaryTextColor)
                }
                Text("\(seatNumber)")
                    .font(.system(size: height * 0.14, design: .rounded))
                    .foregroundStyle(style.secondaryTextColor)
            }
            .padding(.top, 4)
            .padding(.trailing, 5)
        }
    }

    private var accessibilityText: String {
        if let student { return L("chart.seat_of", seatNumber, student.firstName) }
        if desk.isDisabled { return L("chart.seat_disabled", seatNumber) }
        return L("chart.seat_empty", seatNumber)
    }
}
