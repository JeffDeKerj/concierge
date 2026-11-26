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

    @Test func atRestItShowsTroubleThenSleepThenThePointer() {
        #expect(Face.expression(state: .idle, hasError: true, silenced: true, hovered: true) == .trouble)
        #expect(Face.expression(state: .idle, hasError: false, silenced: true, hovered: true) == .asleep)
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

/// Not a check: with FACE_SHEET set to a file path, draws every style in
/// every expression into that PNG, to look at the faces without opening the app.
@MainActor
struct FaceSheetTests {
    @Test func drawTheSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["FACE_SHEET"] else { return }
        let expressions: [Face.Expression] = [.idle, .listening, .thinking, .speaking, .asleep, .trouble]
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
                Text("in the window").frame(width: 150)
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
                    }
                    .frame(width: 150)
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
        try save(PlacesSheet(), to: path.replacingOccurrences(of: ".png", with: "-places.png"))
    }

    private func save(_ view: some View, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}

/// Small pictures of the window with the face in different places.
private struct PlacesSheet: View {
    private let lines: [CGFloat] = [120, 236, 244, 228, 240, 150, 0, 90, 232, 240, 180, 0, 70, 236, 200]

    private func face(_ expression: Face.Expression, _ side: CGFloat) -> some View {
        Canvas { context, size in
            FaceDrawing(style: .robot, pose: Face.pose(for: expression), time: 1.2, level: 0.6).draw(in: &context, size: size)
        }
        .frame(width: side, height: side)
    }

    private func window(boxGap: CGFloat = 0, @ViewBuilder over: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.09, green: 0.10, blue: 0.12))
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14))
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.22)).frame(width: 8, height: 8) }
                    Text("Thursday 26 November").font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 6)
                    Spacer()
                }
                .frame(height: 30).padding(.horizontal, 10)
                Color.white.opacity(0.1).frame(height: 1)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, width in
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(width == 0 ? 0 : 0.09)).frame(width: max(width, 1), height: 8)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Color.white.opacity(0.1).frame(height: 1)
                HStack {
                    Spacer().frame(width: boxGap)
                    RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.22)).frame(height: 22)
                        .overlay(alignment: .leading) {
                            Text("Ask a follow-up…").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.leading, 7)
                        }
                }
                .padding(10)
            }
            over()
        }
        .frame(width: 280, height: 380)
    }

    private func option(_ name: String, _ note: String, @ViewBuilder picture: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            picture()
            Text(name).font(.title3.bold()).foregroundStyle(.white)
            Text(note).font(.callout).foregroundStyle(.secondary).frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 280, alignment: .topLeading)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            option("A. Beside the question box", "Where it is now. Small, always in view, out of the page's way.") {
                window(boxGap: 50) { face(.idle, 48).position(x: 34, y: 352) }
            }
            option("B. In the top bar", "Small, next to the date. It is the first thing you see, and the page keeps all its room.") {
                window { face(.idle, 30).position(x: 188, y: 15) }
            }
            option("C. Hovering over the page", "Floats over a corner of the page and bobs gently. You can drag it anywhere, and it stays there.") {
                window {
                    face(.idle, 72).shadow(color: .black.opacity(0.6), radius: 8, y: 4).position(x: 226, y: 286)
                }
            }
            option("D. It moves", "Rests small in the top bar. When you call it, it glides to the middle and grows while you talk, then goes back.") {
                window {
                    Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 12))
                    face(.idle, 30).opacity(0.4).position(x: 188, y: 15)
                    Path { p in
                        p.move(to: CGPoint(x: 184, y: 34))
                        p.addQuadCurve(to: CGPoint(x: 156, y: 106), control: CGPoint(x: 182, y: 78))
                    }
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
                    face(.listening, 130).position(x: 140, y: 180)
                    Text("what's on tomorrow").font(.callout).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                        .position(x: 140, y: 262)
                }
            }
            option("E. On the desktop", "When the window is hidden or covered, it appears in a corner of the screen instead. Already built; works with any of the others.") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(
                        colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.10, green: 0.11, blue: 0.18)],
                        startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.20, green: 0.21, blue: 0.24))
                        .frame(width: 200, height: 230).position(x: 116, y: 150)
                        .overlay { Text("another app").font(.caption).foregroundStyle(.tertiary).position(x: 116, y: 150) }
                    face(.listening, 84).position(x: 226, y: 318)
                    Text("Listening…").font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                        .position(x: 226, y: 366)
                }
                .frame(width: 280, height: 380)
            }
        }
        .padding(28)
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
        .environment(\.colorScheme, .dark)
    }
}
