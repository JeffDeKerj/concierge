import Foundation
import Testing
@testable import Concierge

struct SilenceTests {
    @Test func silenceLastsUntilItsTime() {
        var s = ConciergeSettings()
        let now = Date()
        #expect(!s.isSilenced(at: now))
        s.silence(until: Silence.forAnHour(from: now))
        #expect(s.isSilenced(at: now))
        #expect(!s.isSilenced(at: now.addingTimeInterval(3700)))
        s.silence(until: nil)
        #expect(!s.isSilenced(at: now))
    }

    @Test func untilTomorrowEndsAtMidnight() {
        let now = Date()
        let end = Silence.untilTomorrow(from: now)
        #expect(Calendar.current.isDate(end, inSameDayAs: now.addingTimeInterval(86400)))
        #expect(Calendar.current.component(.hour, from: end) == 0)
    }

    @Test func voicesAreEnglishAndNotNovelty() {
        for v in Speaker.voices() {
            #expect(v.language.hasPrefix("en"))
            #expect(!v.voiceTraits.contains(.isNoveltyVoice))
        }
    }
}
