import Foundation
import Testing
@testable import SeatingChart

@Suite("Countdown formatting and parsing")
struct TimerTests {

    // MARK: - Formatting

    @Test("Formats as m:ss below an hour")
    func formatsMinutesAndSeconds() {
        #expect(Countdown.format(0) == "0:00")
        #expect(Countdown.format(9) == "0:09")
        #expect(Countdown.format(60) == "1:00")
        #expect(Countdown.format(299) == "4:59")
        #expect(Countdown.format(720) == "12:00")
    }

    @Test("Formats as h:mm:ss from an hour up")
    func formatsHours() {
        #expect(Countdown.format(3600) == "1:00:00")
        #expect(Countdown.format(3900) == "1:05:00")
        #expect(Countdown.format(3661) == "1:01:01")
    }

    /// A fresh five-minute timer should read 5:00, not 4:59, so the readout is
    /// rounded up rather than truncated.
    @Test("Rounds up so a full duration reads whole")
    func roundsUp() {
        #expect(Countdown.format(299.4) == "5:00")
        #expect(Countdown.format(0.1) == "0:01")
    }

    @Test("Never shows a negative time")
    func clampsNegatives() {
        #expect(Countdown.format(-5) == "0:00")
    }

    // MARK: - Parsing

    @Test("A bare number means minutes")
    func parsesBareNumberAsMinutes() {
        #expect(Countdown.parse("7") == 420)
        #expect(Countdown.parse("1.5") == 90)
        #expect(Countdown.parse("  3  ") == 180)
    }

    @Test("Unit suffixes are honoured")
    func parsesUnits() {
        #expect(Countdown.parse("90s") == 90)
        #expect(Countdown.parse("45 sec") == 45)
        #expect(Countdown.parse("2m") == 120)
        #expect(Countdown.parse("2 min") == 120)
        #expect(Countdown.parse("10 minutes") == 600)
        #expect(Countdown.parse("30 SECONDS") == 30)
    }

    @Test("Clock forms parse as m:ss and h:mm:ss")
    func parsesClockForms() {
        #expect(Countdown.parse("2:30") == 150)
        #expect(Countdown.parse("0:45") == 45)
        #expect(Countdown.parse("12:00") == 720)
        #expect(Countdown.parse("1:05:00") == 3900)
    }

    /// `2:75` is a typo, not 195 seconds.
    @Test("Rejects clock forms with an out-of-range component")
    func rejectsOverflowingClockComponents() {
        #expect(Countdown.parse("2:75") == nil)
        #expect(Countdown.parse("1:60:00") == nil)
        #expect(Countdown.parse("1:2:3:4") == nil)
        #expect(Countdown.parse("2:") == nil)
        #expect(Countdown.parse(":30") == nil)
        #expect(Countdown.parse("a:30") == nil)
    }

    @Test("Rejects what it cannot read")
    func rejectsGarbage() {
        #expect(Countdown.parse("") == nil)
        #expect(Countdown.parse("   ") == nil)
        #expect(Countdown.parse("abc") == nil)
        #expect(Countdown.parse("-5") == nil)
    }

    @Test("Clamps rather than rejecting an in-range typo")
    func clampsOutOfRange() {
        #expect(Countdown.parse("0") == Countdown.minDuration)
        #expect(Countdown.parse("0s") == Countdown.minDuration)
        #expect(Countdown.parse("9999") == Countdown.maxDuration)
    }

    // MARK: - Presets

    @Test("Presets are the four advertised lengths")
    func presetDurations() {
        #expect(TimerPreset.allCases.map(\.minutes) == [1, 3, 5, 10])
        #expect(TimerPreset.allCases.map(\.duration) == [60, 180, 300, 600])
    }

    @Test("Every preset round-trips through the formatter")
    func presetsFormat() {
        #expect(TimerPreset.allCases.map { Countdown.format($0.duration) }
            == ["1:00", "3:00", "5:00", "10:00"])
    }

    // MARK: - Sounds

    @Test("Every finish sound names a real system sound")
    func soundsExist() {
        for sound in FinishSound.allCases {
            let url = URL(fileURLWithPath: "/System/Library/Sounds/\(sound.systemName).aiff")
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "missing system sound: \(sound.systemName)")
        }
    }
}
