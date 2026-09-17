import AppKit

/// Playing the finish chime. Its own tiny type so `TimerModel` stays AppKit-free.
enum TimerSound {
    /// System sounds live in `/System/Library/Sounds`, which `NSSound(named:)`
    /// searches — nothing has to be bundled with the app. Plays even when the
    /// app is not frontmost, which is the whole point during a slideshow.
    static func play(_ sound: FinishSound) {
        NSSound(named: NSSound.Name(sound.systemName))?.play()
    }
}
