import SwiftUI

/// The name picker tab: every control lives here, the overlay only displays.
struct NamePickerView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            stage
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NamePickerOverlayController.shared.toggle(store: store)
                } label: {
                    Label(store.namePicker.isOverlayVisible ? L("picker.hide_overlay")
                                                            : L("picker.show_overlay"),
                          systemImage: "macwindow.on.rectangle")
                }
                .help(L("picker.overlay_help"))
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var picker = store.namePicker
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Picker(L("picker.class"), selection: $picker.classID) {
                    Text(L("chart.none")).tag(UUID?.none)
                    ForEach(store.classes) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .frame(maxWidth: 220)

                Picker(L("picker.display"), selection: $picker.displayMode) {
                    Text(L("picker.display.name")).tag(PickerDisplayMode.name)
                    Text(L("picker.display.photo")).tag(PickerDisplayMode.photo)
                    Text(L("picker.display.both")).tag(PickerDisplayMode.both)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)

                Spacer()

                Button {
                    store.pickName()
                } label: {
                    Label(L("picker.pick"), systemImage: "dice")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canPickName)
            }

            HStack(spacing: 14) {
                Toggle(L("picker.avoid_repeats"), isOn: $picker.avoidRepeats)

                if picker.avoidRepeats, let students = store.pickerClass?.students,
                   !students.isEmpty {
                    Text(L("picker.progress", picker.pickedCount(in: students), students.count))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button(L("picker.reset")) { picker.reset() }
                        .buttonStyle(.link)
                        .disabled(picker.pickedCount(in: students) == 0)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Preview of what the class sees

    @ViewBuilder
    private var stage: some View {
        if let schoolClass = store.pickerClass {
            if schoolClass.students.isEmpty {
                ContentUnavailableView(L("picker.empty_class"), systemImage: "person.badge.plus",
                                       description: Text(L("picker.empty_class_hint")))
            } else {
                NamePickerOverlayView(cornerRadius: 20)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .frame(maxWidth: 560)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        } else {
            ContentUnavailableView(L("picker.no_class"), systemImage: "dice",
                                   description: Text(L("picker.no_class_hint")))
        }
    }
}
