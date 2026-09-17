import SwiftUI

/// What the class sees. Display only — every control lives in the app window.
/// Type scales with the frame, the way `NamePickerOverlayView` does, so the same
/// view works as a 200pt overlay and as the in-app preview.
struct TimerOverlayView: View {
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
                    // Paused reads as "this is on hold" without needing a label.
                    .opacity(store.timer.phase == .paused ? 0.55 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7),
                               value: store.timer.phase)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if store.timer.phase == .finished {
            // Same shape as the picker's "photo and name" layout, so the two
            // overlays read as one family.
            VStack(spacing: size.height * 0.05) {
                donePicture(size: min(size.width, size.height) * 0.46)
                Text(L("timer.done"))
                    .font(.system(size: max(11, size.height * 0.18),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
        } else {
            VStack(spacing: size.height * 0.08) {
                Text(Countdown.format(store.timer.remaining))
                    // Monospaced digits, or the whole readout shifts sideways
                    // every time a 1 ticks past.
                    .font(.system(size: max(11, size.height * 0.34),
                                  weight: .semibold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                progressBar(in: size)
            }
        }
    }

    /// The part that still reads from the back of the room once the digits are
    /// too small to parse at a glance.
    private func progressBar(in size: CGSize) -> some View {
        let height = max(3, size.height * 0.03)
        return GeometryReader { bar in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: bar.size.width * store.timer.progress)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func donePicture(size: CGFloat) -> some View {
        if let name = store.timer.doneImageFileName,
           let image = PhotoCache.image(at: store.photoURL(named: name)) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.08))
        } else {
            Image(systemName: "party.popper.fill")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
    }
}
