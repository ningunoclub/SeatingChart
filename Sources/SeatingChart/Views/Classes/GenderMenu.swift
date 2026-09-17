import SwiftUI

extension Gender {
    var symbolName: String {
        switch self {
        case .male: "figure.stand"
        case .female: "figure.stand.dress"
        case .unspecified: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .male: L("class.gender.male")
        case .female: L("class.gender.female")
        case .unspecified: L("class.gender.unspecified")
        }
    }
}

/// The three choices, as menu entries. Shared so the inline control in a student
/// row and the row's `⋯` menu can never drift apart.
struct GenderMenuItems: View {
    @Binding var gender: Gender

    var body: some View {
        ForEach(Gender.allCases) { choice in
            Button {
                gender = choice
            } label: {
                // A checkmark rather than a `Picker`: the inline control's label
                // is a bare symbol, and `Picker` insists on showing its own.
                Label(choice.label,
                      systemImage: choice == gender ? "checkmark" : choice.symbolName)
            }
        }
    }
}

/// Inline gender control for a student row — one click, three choices, no dialog,
/// so a whole class can be set in a single pass down the list.
struct GenderMenu: View {
    @Binding var gender: Gender

    var body: some View {
        Menu {
            GenderMenuItems(gender: $gender)
        } label: {
            Image(systemName: gender.symbolName)
                .foregroundStyle(gender == .unspecified ? AnyShapeStyle(.tertiary)
                                                        : AnyShapeStyle(.secondary))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .help(L("class.gender_help"))
        .accessibilityLabel(L("class.gender"))
        .accessibilityValue(gender.label)
    }
}
