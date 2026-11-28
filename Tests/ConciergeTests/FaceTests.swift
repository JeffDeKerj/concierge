import AppKit
import AVFoundation
import SwiftUI
import Testing
@testable import Concierge

struct FaceExpressionTests {
    @Test func whatItIsDoingWins() {
        #expect(Face.expression(state: .listening(""), hasError: true, silenced: true, hovered: true) == .listening)
        #expect(Face.expression(state: .thinking, hasError: false, silenced: false, hovered: false) == .thinking)
        #expect(Face.expression(state: .speaking, hasError: false, silenced: true, hovered: false) == .speaking)
    }

    @Test func atRestItShowsTroubleThenSleepThenDeafnessThenThePointer() {
        #expect(Face.expression(state: .idle, hasError: true, silenced: true, hovered: true, deaf: true) == .trouble)
        #expect(Face.expression(state: .idle, hasError: false, silenced: true, hovered: true, deaf: true) == .asleep)
        #expect(Face.expression(state: .idle, hasError: false, silenced: false, hovered: true, deaf: true) == .deaf)
        #expect(Face.expression(state: .idle, hasError: false, silenced: false, hovered: false, deaf: true) == .deaf)
        #expect(Face.expression(state: .listening(""), hasError: false, silenced: false, hovered: false, deaf: true) == .listening)
        #expect(Face.expression(state: .idle, hasError: false, silenced: false, hovered: true) == .attentive)
        #expect(Face.expression(state: .idle, hasError: false, silenced: false, hovered: false) == .idle)
    }
}

struct FaceMotionTests {
    @Test func aPoseMixesFromOneToTheOther() {
        let a = Face.pose(for: .idle), b = Face.pose(for: .listening)
        #expect(a.mixed(with: b, 0) == a)
        #expect(a.mixed(with: b, 1) == b)
        let half = a.mixed(with: b, 0.5)
        #expect(half.ears == 0.5)
        #expect(half.eyeWidth > a.eyeWidth && half.eyeWidth < b.eyeWidth)
    }

    @Test func aChangeOfExpressionStartsFromWhereTheFaceIs() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var motion = Face.Motion(.idle)
        #expect(motion.pose(at: start) == Face.pose(for: .idle))
        #expect(!motion.isChanging(at: start))
        motion.change(to: .listening, at: start)
        #expect(motion.isChanging(at: start.addingTimeInterval(0.2)))
        let midway = motion.pose(at: start.addingTimeInterval(Face.changeTime / 2))
        #expect(abs(midway.ears - 0.5) < 0.001)
        // Interrupted halfway: it goes on from there, without a jump.
        let turn = start.addingTimeInterval(Face.changeTime / 2)
        motion.change(to: .thinking, at: turn)
        #expect(motion.pose(at: turn) == midway)
        #expect(motion.pose(at: turn.addingTimeInterval(1)) == Face.pose(for: .thinking))
        #expect(!motion.isChanging(at: turn.addingTimeInterval(1)))
    }

    @Test func itBlinksNowAndThenAndIsMostlyOpen() {
        let steps = (0..<6000).map { Face.blink(at: Double($0) * 0.01) }
        #expect(steps.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(steps.contains { $0 < 0.1 })
        // Open more than nine tenths of a minute.
        #expect(steps.filter { $0 == 1 }.count > 5400)
    }

    @Test func theGazeStaysInsideTheGlassAndMovesSmoothly() {
        var last = Face.gaze(at: 0)
        for i in 1..<3000 {
            let now = Face.gaze(at: Double(i) * 0.01)
            #expect(abs(now.x) <= 1 && abs(now.y) <= 1)
            #expect(abs(now.x - last.x) < 0.2 && abs(now.y - last.y) < 0.2)
            last = now
        }
    }

    @Test func theMouthOpensWithTheVoice() {
        let pose = Face.pose(for: .speaking)
        let quiet = FaceDrawing(pose: pose, time: 3, level: 0).mouthOpening
        let loud = FaceDrawing(pose: pose, time: 3, level: 1).mouthOpening
        #expect(loud.height > quiet.height + 5)
        #expect(loud.weight == 1)
        // At rest the mouth is the closed smile, whatever the voice does.
        #expect(FaceDrawing(pose: Face.pose(for: .idle), time: 3, level: 1).mouthOpening.weight == 0)
        // Listening rounds it into a small "o".
        let listening = FaceDrawing(pose: Face.pose(for: .listening), time: 3, level: 0).mouthOpening
        #expect(listening.weight == 1 && listening.width < quiet.width && listening.height > quiet.height)
    }

    @Test func aRestingFaceIsDrawnSlowlyExceptAroundABlink() {
        // Walk a minute the way the screen does, one picture after the other.
        var time = 0.0, pictures = 0, missed = 0
        var lastOpen = 1.0
        while time < 60 {
            let step = Face.pictureInterval(.idle, at: time, changing: false)
            // No blink may start and end between two slow pictures.
            if step == Face.restInterval, lastOpen == 1 {
                for k in 1..<10 where Face.blink(at: time + step * Double(k) / 10) < 0.5 { missed += 1 }
            }
            lastOpen = Face.blink(at: time)
            time += step
            pictures += 1
        }
        #expect(missed == 0)
        // Far fewer than the 1800 of a steady full rate.
        #expect(pictures < 900)
        #expect(Face.pictureInterval(.speaking, at: 5, changing: false) == Face.fullInterval)
        #expect(Face.pictureInterval(.asleep, at: 5, changing: false) == Face.restInterval)
        #expect(Face.pictureInterval(.asleep, at: 5, changing: true) == Face.fullInterval)
    }

    @Test func theMadeUpVoiceStaysInRange() {
        let levels = (0..<2000).map { Face.babble(at: Double($0) * 0.01) }
        #expect(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(levels.max()! > 0.6)
    }
}

struct VoiceLoudnessTests {
    private func tone(_ amplitude: Float, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let frames = AVAudioFrameCount(24000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.3)
        }
        return buffer
    }

    @Test func loudnessFollowsTheSoundThirtyStepsASecond() {
        let steps = VoiceIO.loudness(of: [tone(0.8, seconds: 1), tone(0, seconds: 0.5), tone(0.2, seconds: 0.5)])
        #expect(steps.count == 60)
        #expect(steps[10] > 0.95)
        #expect(steps[40] == 0)
        // A quiet part still moves the mouth, less than a loud one.
        #expect(steps[55] > 0.3 && steps[55] < 0.7)
    }

    @Test func silenceAndNothingGiveNoLoudness() {
        #expect(VoiceIO.loudness(of: []).isEmpty)
        #expect(VoiceIO.loudness(of: [tone(0, seconds: 0.2)]).allSatisfy { $0 == 0 })
    }
}

@MainActor
struct FaceStageTests {
    @Test func onStageItIsInTheMiddleAndAtRestUnderItsSpotInTheBar() {
        let size = CGSize(width: 600, height: 800)
        #expect(StagedFace.centre(staged: true, restX: 180, in: size) == CGPoint(x: 300, y: 320))
        let rest = StagedFace.centre(staged: false, restX: 180, in: size)
        #expect(rest.x == 180)
        // Above the top edge: hidden under the bar, where the resting face is.
        #expect(rest.y + StagedFace.restSide / 2 <= 0)
        // Before its spot is known it starts from the middle of the top edge.
        #expect(StagedFace.centre(staged: false, restX: nil, in: size).x == 300)
    }
}

/// Not a check: with FACE_SHEET set to a file path, draws every style in
/// every expression into that PNG, to look at the faces without opening the app.
@MainActor
struct FaceSheetTests {
    @Test func drawTheSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["FACE_SHEET"] else { return }
        let expressions: [Face.Expression] = [.idle, .listening, .thinking, .speaking, .asleep, .trouble, .deaf]
        func face(_ style: Face.Style, _ expression: Face.Expression, _ side: CGFloat, _ time: Double) -> some View {
            Canvas { context, size in
                FaceDrawing(style: style, pose: Face.pose(for: expression), time: time, level: 0.7)
                    .draw(in: &context, size: size)
            }
            .frame(width: side, height: side)
        }
        func sheet(_ styles: [Face.Style], from first: Int) -> some View {
          VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text("").frame(width: 110)
                ForEach(expressions, id: \.self) { expression in
                    Text(String(describing: expression)).frame(width: 170)
                }
                Text("in the window").frame(width: 210)
            }
            .font(.title3).foregroundStyle(.secondary)
            ForEach(Array(styles.enumerated()), id: \.offset) { row, style in
                HStack(spacing: 16) {
                    Text("\(first + row). \(style.name)").font(.title.bold()).foregroundStyle(.white).frame(width: 110, alignment: .leading)
                    ForEach(Array(expressions.enumerated()), id: \.offset) { i, expression in
                        face(style, expression, 170, 1.2 + Double(i) * 0.37)
                    }
                    HStack(spacing: 14) {
                        face(style, .idle, 60, 7.9)
                        face(style, .asleep, 60, 8.3)
                        face(style, .deaf, 60, 8.7)
                        // The size of the top bar.
                        face(style, .deaf, 30, 8.7)
                    }
                    .frame(width: 210)
                }
            }
        }
          .padding(28)
          .background(Color(red: 0.06, green: 0.07, blue: 0.08))
          .environment(\.colorScheme, .dark)
        }
        let others = Face.Style.allCases.filter { !Face.Style.animals.contains($0) }
        try save(sheet(others, from: 1), to: path)
        try save(sheet(Face.Style.animals, from: others.count + 1), to: path.replacingOccurrences(of: ".png", with: "-animals.png"))
    }

    private func save(_ view: some View, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
