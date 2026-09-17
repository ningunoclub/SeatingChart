import AppKit
import SwiftUI

/// Floating panel for the name picker. It has to sit above a running PowerPoint
/// slideshow on a second monitor and never take the keyboard away from it, so
/// it refuses key and main status outright — there is nothing to type into it.
final class NamePickerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the single panel instance. Keeping the panel alive across hide/unhide is
/// what makes it come back exactly where the user left it.
final class NamePickerOverlayController {
    static let shared = NamePickerOverlayController()

    private static let autosaveName = "NamePickerOverlay"
    private static let defaultSize = NSSize(width: 420, height: 260)

    private var panel: NamePickerPanel?

    func toggle(store: AppStore) {
        if panel?.isVisible == true {
            hide(store: store)
        } else {
            show(store: store)
        }
    }

    func show(store: AppStore) {
        let panel = panel ?? makePanel(store: store)
        self.panel = panel
        constrainToVisibleScreen(panel)
        // Regardless, so it appears while PowerPoint is still frontmost.
        panel.orderFrontRegardless()
        store.namePicker.isOverlayVisible = true
    }

    func hide(store: AppStore) {
        panel?.orderOut(nil)
        store.namePicker.isOverlayVisible = false
    }

    /// Called at termination so the frame lands in the defaults before we go.
    func close() {
        guard let panel else { return }
        panel.saveFrame(usingName: Self.autosaveName)
        panel.close()
        self.panel = nil
    }

    // MARK: - Panel construction

    private func makePanel(store: AppStore) -> NamePickerPanel {
        let panel = NamePickerPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            // `.nonactivatingPanel` is what lets the user drag it around without
            // pulling focus out of the presentation.
            styleMask: [.titled, .resizable, .fullSizeContentView,
                        .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = L("picker.overlay_window")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        // No visible title bar to grab, so the whole card is the drag handle.
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        // NSPanel hides itself when the app deactivates — which is precisely
        // when this window needs to be on screen.
        panel.hidesOnDeactivate = false
        // `.floating` sits below a PowerPoint slideshow; this clears it.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 220, height: 120)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        let host = NSHostingView(rootView: NamePickerOverlayView().environment(store))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        if !panel.setFrameUsingName(Self.autosaveName) {
            positionTopRight(panel)
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        return panel
    }

    // MARK: - Placement

    /// A frame saved on a monitor that is no longer attached would restore
    /// off-screen, leaving the user with an invisible overlay.
    private func constrainToVisibleScreen(_ panel: NSPanel) {
        let frame = panel.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !onScreen { positionTopRight(panel) }
    }

    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24,
                                     y: visible.maxY - size.height - 24))
    }
}
