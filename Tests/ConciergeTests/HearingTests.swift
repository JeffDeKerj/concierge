import Foundation
import Testing
@testable import Concierge

struct SilenceWatchTests {
    @Test func aMinuteOfNothingIsDeafAndIsSaidOnce() {
        var watch = SilenceWatch()
        for _ in 1..<SilenceWatch.looksToDeaf {
            #expect(watch.look(silent: true) == nil)
        }
        #expect(!watch.isDeaf)
        #expect(watch.look(silent: true) == .deaf)
        #expect(watch.isDeaf)
        // It stays deaf without saying so again.
        #expect(watch.look(silent: true) == nil)
        #expect(watch.isDeaf)
    }

    @Test func soundEndsItAndStartsTheCountAgain() {
        var watch = SilenceWatch()
        for _ in 0..<SilenceWatch.looksToDeaf { _ = watch.look(silent: true) }
        #expect(watch.look(silent: false) == .hearsAgain)
        #expect(!watch.isDeaf)
        #expect(watch.look(silent: false) == nil)
        // A short silence in a live room is nothing.
        for _ in 0..<SilenceWatch.looksToDeaf - 1 { _ = watch.look(silent: true) }
        #expect(watch.look(silent: false) == nil)
        #expect(watch.look(silent: true) == nil)
    }

    @Test func forgettingSaysItHearsAgainOnlyWhenItWasDeaf() {
        var watch = SilenceWatch()
        #expect(watch.forget() == nil)
        for _ in 0..<SilenceWatch.looksToDeaf { _ = watch.look(silent: true) }
        #expect(watch.forget() == .hearsAgain)
        #expect(watch.forget() == nil)
    }
}

@MainActor
struct HearingTests {
    @Test func theOwnerIsToldOnceWhenHearingIsLost() {
        var told: [String] = []
        let hearing = Hearing(lidClosed: { true }, tell: { told.append($0) })
        #expect(hearing.problem == nil && hearing.words == nil)
        hearing.set(.silent(microphone: "Loop120"))
        hearing.set(.silent(microphone: "Loop120"))
        #expect(told.count == 1)
        #expect(told[0].contains("Loop120") && told[0].contains("Switch the headset on"))
        #expect(hearing.words == told[0])
        // Another reason while still deaf is shown, not announced.
        hearing.set(.noMicrophone)
        #expect(told.count == 1)
        #expect(hearing.problem == .noMicrophone)
        hearing.set(nil)
        #expect(hearing.words == nil)
        hearing.set(.noMicrophone)
        #expect(told.count == 2)
    }

    @Test func theAdviceFollowsTheLid() {
        let silent = Hearing.Problem.silent(microphone: "Loop120")
        // Lid closed: the Mac's own microphone is cut, so it is not offered.
        #expect(!Hearing.words(for: silent, lidClosed: true).contains("own microphone"))
        #expect(Hearing.words(for: silent, lidClosed: false).contains("own microphone"))
        #expect(Hearing.words(for: .noMicrophone, lidClosed: true).contains("lid is closed"))
        #expect(!Hearing.words(for: .noMicrophone, lidClosed: false).contains("lid"))
    }
}
