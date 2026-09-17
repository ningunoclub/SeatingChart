import AppKit
import SwiftUI

/// The timer tab: every control lives here, the overlay only displays.
struct TimerView: View {
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
                    TimerOverlayController.shared.toggle(store: store)
                } label: {
                    Label(store.timer.isOverlayVisible ? L("timer.hide_overlay")
                                                       : L("timer.show_overlay"),
                          systemImage: "macwindow.on.rectangle")
                }
                .help(L("timer.overlay_help"))
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var timer = store.timer
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Picker(L("timer.preset"), selection: presetSelection) {
                    ForEach(TimerPreset.allCases) { preset in
                        Text(L("timer.minutes", preset.minutes)).tag(Optional(preset))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)

                TextField(L("timer.custom_placeholder"), text: $timer.customInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .onSubmit { timer.applyCustomInput() }
                    .help(L("timer.custom_help"))

                Spacer()

                Button(L("timer.reset")) { timer.reset() }
                    .disabled(timer.phase == .idle)

                Button {
                    timer.toggle()
                } label: {
                    Label(primaryLabel, systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 14) {
                Toggle(L("timer.sound_enabled"), isOn: $timer.soundEnabled)

                Picker(L("timer.sound"), selection: $timer.sound) {
                    // The macOS sound names are product names, not prose — they
                    // stay as-is in both languages.
                    ForEach(FinishSound.allCases) { sound in
                        Text(sound.systemName).tag(sound)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .disabled(!timer.soundEnabled)

                Button {
                    timer.previewSound()
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
                .disabled(!timer.soundEnabled)
                .help(L("timer.preview_sound"))

                Divider().frame(height: 16)

                Menu {
                    Button(L("timer.choose_picture")) { pickPicture() }
                    if timer.doneImageFileName != nil {
                        Button(L("timer.remove_picture"), role: .destructive) {
                            store.removeTimerImage()
                        }
                    }
                } label: {
                    Label(L("timer.picture"), systemImage: "photo")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("timer.picture_help"))

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Writing through a preset picks that duration; a custom time matches no
    /// preset, which leaves the segmented control showing nothing selected.
    private var presetSelection: Binding<TimerPreset?> {
        Binding(
            get: { store.timer.selectedPreset },
            set: { if let preset = $0 { store.timer.select(preset) } }
        )
    }

    private var primaryLabel: String {
        switch store.timer.phase {
        case .idle: L("timer.start")
        case .running: L("timer.pause")
        case .paused: L("timer.resume")
        case .finished: L("timer.restart")
        }
    }

    private func pickPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("timer.picture_prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setTimerImage(from: url)
    }

    // MARK: - Preview of what the class sees

    private var stage: some View {
        TimerOverlayView(cornerRadius: 20)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: 560)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
