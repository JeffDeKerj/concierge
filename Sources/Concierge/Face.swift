import Foundation

/// Concierge's face: which expression it wears, and the numbers the drawing
/// follows. Everything here is a plain function of its inputs, so the face
/// looks the same for the same moment and can be tested without a screen.
enum Face {
    /// The character that wears the expressions, from the least like a
    /// person to the most.
    enum Style: String, CaseIterable, Identifiable {
        case halo, sprout, robot, kitty, android, bellhop, owl, penguin, pup
        /// The animals, each in a concierge's hat.
        static let animals: [Style] = [.owl, .penguin, .pup]
        var id: String { rawValue }
        var name: String {
            switch self {
            case .halo: "Halo"
            case .sprout: "Sprout"
            case .robot: "Robot"
            case .kitty: "Kitty"
            case .android: "Android"
            case .bellhop: "Bellhop"
            case .owl: "Owl"
            case .penguin: "Penguin"
            case .pup: "Pup"
            }
        }
    }

    enum Expression: Equatable, CaseIterable {
        /// Silenced: it does not answer to its name.
        case asleep
        /// Waiting, looking about.
        case idle
        /// The pointer is on it.
        case attentive
        case listening, thinking, speaking
        /// The last conversation ended with an error.
        case trouble
        /// The microphone sends nothing: a hand at its ear.
        case deaf
    }

    /// The expression for what Concierge is doing.
    static func expression(state: Conversation.State, hasError: Bool,
                           silenced: Bool, hovered: Bool, deaf: Bool = false) -> Expression {
        switch state {
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .idle:
            if hasError { return .trouble }
            if silenced { return .asleep }
            // Kept under the pointer too: the tooltip says what to do.
            if deaf { return .deaf }
            return hovered ? .attentive : .idle
        }
    }

    /// One arrangement of the face. Lengths are in hundredths of the face's
    /// side; the drawing moves from one pose to the next by mixing them.
    struct Pose: Equatable {
        var eyeWidth = 11.0
        var eyeHeight = 14.5
        /// Where the eyes look, -1 to 1 each way.
        var lookX = 0.0
        var lookY = 0.0
        /// 0 for open eyes, 1 for the closed arcs of sleep.
        var closed = 0.0
        /// How much the gaze roams by itself.
        var wander = 0.0
        /// The curve of the mouth: 1 smiles, -1 frowns.
        var smile = 0.0
        /// How far the mouth rounds into an "o" by itself.
        var gape = 0.0
        /// How much the mouth is three bobbing dots: it is thinking.
        var wave = 0.0
        /// How much the mouth follows the voice.
        var talk = 0.0
        /// The rings at the ears while it listens.
        var ears = 0.0
        /// A hand cupped behind its ear: it cannot hear.
        var cup = 0.0
        /// Head tilt in degrees.
        var tilt = 0.0
        /// How brightly the eyes, mouth and antenna shine.
        var glow = 0.85
        var red = 0.33
        var green = 0.90
        var blue = 0.84

        /// This pose moved `t` of the way (0 to 1) towards `other`.
        func mixed(with other: Pose, _ t: Double) -> Pose {
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
            return Pose(
                eyeWidth: mix(eyeWidth, other.eyeWidth), eyeHeight: mix(eyeHeight, other.eyeHeight),
                lookX: mix(lookX, other.lookX), lookY: mix(lookY, other.lookY),
                closed: mix(closed, other.closed), wander: mix(wander, other.wander),
                smile: mix(smile, other.smile), gape: mix(gape, other.gape), wave: mix(wave, other.wave),
                talk: mix(talk, other.talk), ears: mix(ears, other.ears), cup: mix(cup, other.cup),
                tilt: mix(tilt, other.tilt), glow: mix(glow, other.glow),
                red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
        }
    }

    static func pose(for expression: Expression) -> Pose {
        switch expression {
        case .asleep:
            Pose(closed: 1, smile: 0.8, tilt: 5, glow: 0.6, red: 0.52, green: 0.80, blue: 0.92)
        case .idle:
            Pose(wander: 1, smile: 1)
        case .attentive:
            Pose(eyeWidth: 12.5, eyeHeight: 17, smile: 1, glow: 1)
        case .listening:
            Pose(eyeWidth: 12.5, eyeHeight: 17, lookY: -0.1, gape: 0.6, ears: 1, glow: 1,
                 red: 0.42, green: 0.78, blue: 1.0)
        case .thinking:
            Pose(eyeHeight: 12.5, lookX: 0.75, lookY: -0.8, wave: 1, tilt: -6, glow: 0.95,
                 red: 0.74, green: 0.66, blue: 1.0)
        case .speaking:
            Pose(eyeWidth: 11.5, talk: 1, glow: 1, red: 0.42, green: 0.96, blue: 0.76)
        case .trouble:
            Pose(eyeWidth: 10, eyeHeight: 10.5, lookY: 0.35, smile: -0.6, glow: 0.85,
                 red: 1.0, green: 0.74, blue: 0.42)
        case .deaf:
            // It leans towards the hand and looks that way, puzzled.
            Pose(eyeWidth: 12, eyeHeight: 16, lookX: 0.7, lookY: -0.15, smile: -0.25, cup: 1, tilt: 7,
                 glow: 0.95, red: 1.0, green: 0.84, blue: 0.36)
        }
    }

    /// How long a change of expression takes.
    static let changeTime = 0.35

    /// The face on its way from one expression to the next.
    struct Motion {
        private var from: Pose
        private var to: Pose
        private var changed = Date.distantPast

        init(_ expression: Expression) {
            from = Face.pose(for: expression)
            to = from
        }

        /// Starts towards `expression` from wherever the face is at `now`, even mid-change.
        mutating func change(to expression: Expression, at now: Date) {
            from = pose(at: now)
            to = Face.pose(for: expression)
            changed = now
        }

        func pose(at now: Date) -> Pose {
            from.mixed(with: to, Face.ease(now.timeIntervalSince(changed) / Face.changeTime))
        }

        /// The change is drawn at the full rate until then.
        var changingUntil: Date { changed.addingTimeInterval(Face.changeTime + 0.1) }
        func isChanging(at now: Date) -> Bool { now < changingUntil }
    }

    /// Slow at both ends, 0 to 1.
    static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// A steady number between 0 and 1 for a whole number, different for each `salt`.
    static func noise(_ n: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(salt) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 30; x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27; x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
    }

    private static let blinkEvery = 3.7
    private static let blinkTime = 0.17

    /// How open the eyes are at `time`: 1 open, 0 shut. One blink at an
    /// uneven moment in every few seconds, now and then two in a row.
    static func blink(at time: Double) -> Double {
        let n = Int((time / blinkEvery).rounded(.down))
        let start = Double(n) * blinkEvery + noise(n, 1) * (blinkEvery - 0.7)
        var starts = [start]
        if noise(n, 2) > 0.78 { starts.append(start + 0.3) }
        for s in starts where time >= s && time <= s + blinkTime {
            return 1 - sin(.pi * (time - s) / blinkTime)
        }
        return 1
    }

    private static let glanceEvery = 2.9

    /// Where the roaming gaze looks at `time`, -1 to 1 each way. It rests
    /// straight ahead about half the time.
    static func gaze(at time: Double) -> (x: Double, y: Double) {
        func target(_ n: Int) -> (x: Double, y: Double) {
            if noise(n, 3) < 0.45 { return (0, 0) }
            return (noise(n, 4) * 2 - 1, (noise(n, 5) * 2 - 1) * 0.6)
        }
        let n = Int((time / glanceEvery).rounded(.down))
        let t = ease((time - Double(n) * glanceEvery) / 0.3)
        let a = target(n - 1), b = target(n)
        return (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    /// A made-up voice level, 0 to 1, for speech whose sound the app cannot
    /// measure: syllables with short gaps.
    static func babble(at time: Double) -> Double {
        let syllables = abs(sin(time * 9.1)) * 0.5 + abs(sin(time * 14.3 + 1)) * 0.3 + abs(sin(time * 5.2 + 2)) * 0.2
        let phrase = min(1, max(0, sin(time * 1.7) * 1.6 + 0.9))
        return syllables * phrase
    }

    /// Seconds between two pictures at rest, and when something moves.
    static let restInterval = 1.0 / 8
    static let fullInterval = 1.0 / 30

    /// How long until the face should be drawn again. Full rate while it
    /// listens, thinks, speaks, is pointed at or changes expression, and for
    /// a blink or a glance that falls before the next resting picture.
    static func pictureInterval(_ expression: Expression, at time: Double, changing: Bool) -> Double {
        switch expression {
        case .attentive, .listening, .thinking, .speaking:
            return fullInterval
        case .asleep:
            // Closed eyes neither blink nor glance.
            return changing ? fullInterval : restInterval
        case .idle, .trouble, .deaf:
            if changing { return fullInterval }
            let roams = pose(for: expression).wander > 0
            for step in 0...4 {
                let t = time + Double(step) * restInterval / 4
                if blink(at: t) < 1 { return fullInterval }
                let sinceGlance = t - (t / glanceEvery).rounded(.down) * glanceEvery
                if roams && sinceGlance < 0.32 { return fullInterval }
            }
            return restInterval
        }
    }
}
