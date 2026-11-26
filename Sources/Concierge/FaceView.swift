import SwiftUI

/// Concierge's face, alive: it blinks, looks about, and moves smoothly from
/// one expression to the next.
struct FaceView: View {
    var style: Face.Style = .owl
    var expression: Face.Expression
    /// How loud Concierge's voice is at a moment, 0 to 1, when the app can
    /// measure it. Without it the mouth makes its own movement while speaking.
    var level: @MainActor (Date) -> Double? = { _ in nil }
    /// A face that stays put is drawn as pictures on a plain layer, which
    /// is what makes a face that is always on screen cheap. A face that
    /// glides and grows is drawn by SwiftUI, so it can be animated.
    var staysPut = true

    var body: some View {
        Group {
            if staysPut {
                FacePicture(style: style, expression: expression, level: level)
            } else {
                LivingFace(style: style, expression: expression, level: level)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // A picture only: clicks go to whatever holds it.
        .allowsHitTesting(false)
    }
}

/// One picture of the face as a view, for turning into an image.
private struct FaceStill: View {
    var drawing: FaceDrawing
    var side: CGFloat

    var body: some View {
        Canvas { context, size in
            drawing.draw(in: &context, size: size)
        }
        .frame(width: side, height: side)
    }
}

/// The face as a plain AppKit view that puts one picture after the other
/// on its layer. Drawn inside SwiftUI, each new picture made the window
/// (and above all the top bar) work out its layout again, many times a
/// second; a layer's picture can change without anything else noticing.
private struct FacePicture: NSViewRepresentable {
    var style: Face.Style
    var expression: Face.Expression
    var level: @MainActor (Date) -> Double?

    func makeNSView(context: Context) -> PictureView {
        let view = PictureView(expression: expression)
        view.show(style: style, expression: expression, level: level)
        return view
    }

    func updateNSView(_ view: PictureView, context: Context) {
        view.show(style: style, expression: expression, level: level)
    }

    final class PictureView: NSView {
        private var style = Face.Style.owl
        private var expression: Face.Expression
        private var level: @MainActor (Date) -> Double? = { _ in nil }
        private var motion: Face.Motion
        private var next: Timer?
        private var watching: NSObjectProtocol?
        private var renderer: ImageRenderer<FaceStill>?

        init(expression: Face.Expression) {
            self.expression = expression
            motion = Face.Motion(expression)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.contentsGravity = .resizeAspect
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        func show(style: Face.Style, expression: Face.Expression, level: @escaping @MainActor (Date) -> Double?) {
            if expression != self.expression {
                motion.change(to: expression, at: Date())
                self.expression = expression
            }
            self.style = style
            self.level = level
            draw()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let watching { NotificationCenter.default.removeObserver(watching) }
            // Out of sight it stops; back in sight it starts again.
            watching = window.map { window in
                NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                       object: window, queue: .main) { [weak self] _ in self?.draw() }
            }
            draw()
        }

        override func layout() {
            super.layout()
            draw()
        }

        /// Puts the picture for this moment on the layer, and comes back
        /// when the next one is due.
        private func draw() {
            next?.invalidate()
            next = nil
            let side = min(bounds.width, bounds.height)
            guard let window, window.occlusionState.contains(.visible), side > 0 else { return }
            let now = Date(), time = now.timeIntervalSinceReferenceDate
            let still = FaceStill(drawing: FaceDrawing(style: style, pose: motion.pose(at: now), time: time,
                                                       level: level(now) ?? Face.babble(at: time)),
                                  side: side)
            let renderer = self.renderer ?? ImageRenderer(content: still)
            self.renderer = renderer
            renderer.content = still
            renderer.scale = window.backingScaleFactor
            layer?.contents = renderer.cgImage
            let wait = Face.pictureInterval(expression, at: time, changing: motion.isChanging(at: now))
            let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.draw() }
            }
            // Common modes: it keeps going while a menu is open or the window is dragged.
            RunLoop.main.add(timer, forMode: .common)
            next = timer
        }

        deinit {
            next?.invalidate()
            if let watching { NotificationCenter.default.removeObserver(watching) }
        }
    }
}

/// The face drawn by SwiftUI itself, for when it must glide and grow.
private struct LivingFace: View {
    var style: Face.Style
    var expression: Face.Expression
    var level: @MainActor (Date) -> Double?

    @State private var motion: Face.Motion
    /// Whether the window that holds the face can be seen.
    @State private var inSight = true

    init(style: Face.Style, expression: Face.Expression, level: @escaping @MainActor (Date) -> Double?) {
        self.style = style
        self.expression = expression
        self.level = level
        _motion = State(initialValue: Face.Motion(expression))
    }

    var body: some View {
        TimelineView(FaceSchedule(expression: expression, livelyUntil: motion.changingUntil, paused: !inSight)) { timeline in
            let now = timeline.date
            let time = now.timeIntervalSinceReferenceDate
            let drawing = FaceDrawing(style: style, pose: motion.pose(at: now), time: time,
                                      level: level(now) ?? Face.babble(at: time))
            Canvas { context, size in
                drawing.draw(in: &context, size: size)
            }
        }
        .background(SightWatcher(inSight: $inSight))
        .onChange(of: expression) { _, new in
            motion.change(to: new, at: Date())
        }
    }
}

/// Reports whether the window it sits in can be seen: not hidden, not
/// minimised, not covered, not on another desktop.
private struct SightWatcher: NSViewRepresentable {
    @Binding var inSight: Bool

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.report = { seen in
            // Not during a view update.
            DispatchQueue.main.async { if inSight != seen { inSight = seen } }
        }
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        var report: (Bool) -> Void = { _ in }
        private var watching: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let watching { NotificationCenter.default.removeObserver(watching) }
            watching = window.map { window in
                NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                       object: window, queue: .main) { [weak self] _ in self?.tell() }
            }
            tell()
        }

        private func tell() {
            report(window?.occlusionState.contains(.visible) ?? false)
        }

        deinit {
            if let watching { NotificationCenter.default.removeObserver(watching) }
        }
    }
}

/// When the face is drawn again. A resting face barely moves, so it gets a
/// few pictures a second and the full rate only around a blink or a glance;
/// that keeps a face that is always on screen cheap.
struct FaceSchedule: TimelineSchedule {
    var expression: Face.Expression
    /// A change of expression is under way until then.
    var livelyUntil: Date
    /// Nobody can see the face: one picture, then nothing.
    var paused = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(date: startDate, expression: expression, livelyUntil: livelyUntil, paused: paused)
    }

    struct Entries: Sequence, IteratorProtocol {
        var date: Date?
        let expression: Face.Expression
        let livelyUntil: Date
        let paused: Bool

        mutating func next() -> Date? {
            guard let now = date else { return nil }
            if paused {
                date = nil
                return now
            }
            date = now.addingTimeInterval(Face.pictureInterval(expression, at: now.timeIntervalSinceReferenceDate,
                                                               changing: now < livelyUntil))
            return now
        }
    }
}

/// One picture of the face, in one of its styles. Every style has two big
/// eyes with a sparkle, pink cheeks and a small mouth; what differs is the
/// body they sit in.
struct FaceDrawing {
    var style: Face.Style = .owl
    var pose: Face.Pose
    /// Seconds, for everything that moves by itself.
    var time: Double
    /// The voice level, 0 to 1.
    var level: Double

    /// The open mouth, in hundredths of the face's side: it rounds into a
    /// small "o" while listening and opens with the voice while speaking.
    /// `weight` is how much of it shows, against the closed smile.
    var mouthOpening: (width: Double, height: Double, weight: Double) {
        (10 - pose.gape * 4.5,
         2.2 + pose.gape * 4.5 + pose.talk * max(0, level) * 10,
         max(pose.talk, min(1, pose.gape * 3)))
    }

    /// Where a style keeps its features, in hundredths of the face's side.
    private struct Plan {
        var eyeY = 52.0
        var mouthY = 66.5
        var cheekY = 63.5
        /// Dark features on a bright body, not shining ones on dark glass.
        var darkInk = false
        /// Where the rings of listening leave from.
        var ringX = (left: 7.0, right: 93.0)
        var ringY = 55.0
        /// What the spark of thinking circles.
        var spark = (x: 50.0, y: 9.5, radius: 7.2)
        /// Where the letters of sleep start.
        var sleep = (x: 74.0, y: 22.0)
        var eyes = EyeKind.solid
        /// Eyebrows and a small nose: the more human styles.
        var human = false
        /// Eyebrows alone.
        var brows = false
        /// A beak that opens with the voice, in place of a mouth.
        var beak = false
    }

    private enum EyeKind {
        /// One shape of a single colour.
        case solid
        /// A dark eye with a lit ring in it.
        case iris
        /// A white eye with a pupil that looks about.
        case person
    }

    private var plan: Plan {
        switch style {
        case .robot: Plan()
        case .kitty: Plan(eyeY: 55, mouthY: 69, cheekY: 66, ringY: 58, spark: (50, 13, 5.5), sleep: (78, 16))
        case .sprout: Plan(eyeY: 55, mouthY: 69.5, cheekY: 66.5, darkInk: true, ringX: (9, 91), ringY: 58,
                           spark: (50, 12, 8), sleep: (76, 20))
        case .halo: Plan(eyeY: 50, mouthY: 64.5, cheekY: 61.5, ringX: (10, 90), ringY: 54,
                         spark: (50, 16, 0), sleep: (78, 18))
        case .android: Plan(eyeY: 54, mouthY: 75, cheekY: 67, darkInk: true, ringX: (6, 94), ringY: 57,
                            spark: (50, 26.5, 7), sleep: (78, 16), eyes: .iris, human: true)
        case .bellhop: Plan(eyeY: 57, mouthY: 77, cheekY: 69, darkInk: true, ringX: (9, 91), ringY: 60,
                            spark: (59, 8, 6), sleep: (82, 20), eyes: .person, human: true)
        case .owl: Plan(eyeY: 53, mouthY: 67, cheekY: 70, darkInk: true, ringX: (8, 92), ringY: 58,
                        spark: (50, 9, 6), sleep: (84, 18), brows: true, beak: true)
        case .penguin: Plan(eyeY: 54, mouthY: 67, cheekY: 67, darkInk: true, ringX: (8, 92), ringY: 58,
                            spark: (57, 8, 6), sleep: (82, 20), brows: true, beak: true)
        case .pup: Plan(eyeY: 50, mouthY: 75.5, cheekY: 64, darkInk: true, ringX: (4, 96), ringY: 56,
                        spark: (57, 8, 6), sleep: (84, 20), brows: true)
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let u = side / 100
        let plan = plan
        let light = Color(red: pose.red, green: pose.green, blue: pose.blue)
        /// The mood's colour moved towards white (above 0) or towards night blue (below).
        func tint(_ amount: Double) -> Color {
            let to = amount > 0 ? (1.0, 1.0, 1.0) : (0.05, 0.07, 0.16), t = abs(amount)
            return Color(red: pose.red + (to.0 - pose.red) * t, green: pose.green + (to.1 - pose.green) * t,
                         blue: pose.blue + (to.2 - pose.blue) * t)
        }
        let shellTop = Color(red: 0.94, green: 0.96, blue: 0.99)
        let shellLow = Color(red: 0.72, green: 0.77, blue: 0.86)
        let night = [Color(red: 0.09, green: 0.12, blue: 0.20), Color(red: 0.05, green: 0.06, blue: 0.11)]
        let pink = Color(red: 1.0, green: 0.50, blue: 0.66)
        let hair = Color(red: 0.27, green: 0.19, blue: 0.17)
        let ink = [.bellhop, .owl, .pup].contains(style) ? hair
            : plan.darkInk ? Color(red: 0.07, green: 0.09, blue: 0.20) : light
        /// A concierge's small round hat, in the colour of the mood.
        func cap(_ x: Double, _ y: Double, turn: Double) {
            var hat = g
            hat.translateBy(x: x * u, y: y * u)
            hat.rotate(by: .degrees(turn))
            hat.fill(Path(roundedRect: CGRect(x: -14 * u, y: -8 * u, width: 28 * u, height: 14 * u), cornerRadius: 3.5 * u),
                     with: .color(tint(-0.12)))
            hat.fill(Path(CGRect(x: -14 * u, y: 1.5 * u, width: 28 * u, height: 2.6 * u)), with: .color(tint(0.55)))
            hat.fill(Path(ellipseIn: CGRect(x: -2.2 * u, y: -11 * u, width: 4.4 * u, height: 4.4 * u)), with: .color(tint(0.55)))
        }
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x * u, y: y * u, width: w * u, height: h * u)
        }
        func centred(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            rect(x - w / 2, y - h / 2, w, h)
        }
        func pill(_ r: CGRect) -> Path {
            Path(roundedRect: r, cornerRadius: min(r.width, r.height) / 2)
        }
        func upDown(_ colors: [Color], _ top: Double, _ bottom: Double) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: colors), startPoint: point(50, top), endPoint: point(50, bottom))
        }

        var g = context
        g.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        // It breathes, and tilts about its chin.
        g.translateBy(x: 50 * u, y: (62 + sin(time * 1.6) * 0.5) * u)
        g.rotate(by: .degrees(pose.tilt))
        g.translateBy(x: -50 * u, y: -62 * u)

        // A soft light around it, in the colour of its mood.
        g.fill(Path(ellipseIn: centred(50, 56, 100, 100)), with: .radialGradient(
            Gradient(colors: [light.opacity(0.42 * pose.glow), light.opacity(0)]),
            center: point(50, 56), startRadius: 31 * u, endRadius: 50 * u))

        // The rings that leave it while it listens.
        if pose.ears > 0.01 {
            for k in 0..<2 {
                let phase = (time * 0.8 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let style = StrokeStyle(lineWidth: 1.4 * u, lineCap: .round)
                let shade = GraphicsContext.Shading.color(light.opacity(pose.ears * (1 - phase) * 0.9))
                for (x, middle) in [(plan.ringX.left, 180.0), (plan.ringX.right, 0.0)] {
                    var ring = Path()
                    ring.addArc(center: point(x, plan.ringY), radius: (3 + 6 * phase) * u,
                                startAngle: .degrees(middle - 50), endAngle: .degrees(middle + 50), clockwise: false)
                    g.stroke(ring, with: shade, style: style)
                }
            }
        }

        let pulse = pose.glow * (0.75 + 0.25 * sin(time * 2.4))
        var shiningBall: Path?

        // The body.
        switch style {
        case .robot:
            // A pale shell with ear pods, an antenna and a dark glass front.
            g.fill(pill(rect(49, 12, 2, 12)), with: .color(shellLow))
            for x in [6.5, 86.5] {
                g.fill(Path(roundedRect: rect(x, 47, 7, 16), cornerRadius: 3.2 * u), with: .color(shellLow))
                g.fill(pill(rect(x + 2.8, 51, 1.4, 8)), with: .color(light.opacity(0.9)))
            }
            g.fill(Path(roundedRect: rect(12, 22, 76, 68), cornerRadius: 29 * u, style: .continuous),
                   with: upDown([shellTop, shellLow], 22, 90))
            let glass = Path(roundedRect: rect(19.5, 31, 61, 49), cornerRadius: 21 * u, style: .continuous)
            g.fill(glass, with: upDown(night, 31, 80))
            g.fill(glass, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0)]),
                                                startPoint: point(28, 31), endPoint: point(48, 58)))
            shiningBall = Path(ellipseIn: centred(50, 9.5, 8.4, 8.4))

        case .kitty:
            // The same pale shell with two pointed ears, pink inside.
            for flip in [1.0, -1.0] {
                func mirrored(_ x: Double, _ y: Double) -> CGPoint { point(50 - flip * (50 - x), y) }
                var ear = Path()
                ear.move(to: mirrored(15, 46))
                ear.addLine(to: mirrored(20, 9))
                ear.addLine(to: mirrored(47, 29))
                ear.closeSubpath()
                g.fill(ear, with: .color(shellTop))
                g.stroke(ear, with: .color(shellTop), style: StrokeStyle(lineWidth: 5 * u, lineJoin: .round))
                var inner = Path()
                inner.move(to: mirrored(21, 36))
                inner.addLine(to: mirrored(23.5, 18))
                inner.addLine(to: mirrored(36, 28))
                inner.closeSubpath()
                g.fill(inner, with: .color(pink.opacity(0.85)))
                g.stroke(inner, with: .color(pink.opacity(0.85)), style: StrokeStyle(lineWidth: 2 * u, lineJoin: .round))
            }
            g.fill(Path(roundedRect: rect(12, 26, 76, 66), cornerRadius: 29 * u, style: .continuous),
                   with: upDown([shellTop, shellLow], 26, 92))
            let glass = Path(roundedRect: rect(19.5, 35, 61, 48), cornerRadius: 21 * u, style: .continuous)
            g.fill(glass, with: upDown(night, 35, 83))
            g.fill(glass, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0)]),
                                                startPoint: point(28, 35), endPoint: point(48, 60)))

        case .sprout:
            // A soft drop in the colour of its mood, with two leaves on top.
            var stem = Path()
            stem.move(to: point(50, 29))
            stem.addQuadCurve(to: point(50, 14), control: point(47, 21))
            g.stroke(stem, with: .color(tint(-0.25)), style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
            for (dx, turn) in [(-6.5, -28.0), (6.5, 28.0)] {
                var leaf = g
                leaf.translateBy(x: (50 + dx) * u, y: 12.5 * u)
                leaf.rotate(by: .degrees(turn + sin(time * 1.3) * 4))
                leaf.fill(Path(ellipseIn: CGRect(x: -7 * u, y: -3.6 * u, width: 14 * u, height: 7.2 * u)),
                          with: .color(tint(0.25)))
            }
            let body = Path(roundedRect: rect(13, 27, 74, 65), cornerRadius: 31 * u, style: .continuous)
            g.fill(body, with: upDown([tint(0.45), tint(0.05), tint(-0.12)], 27, 92))
            g.fill(Path(ellipseIn: centred(33, 38, 20, 9)), with: .color(Color.white.opacity(0.35)))

        case .halo:
            // Nothing but a dark disc inside a ring of light.
            g.fill(Path(ellipseIn: centred(50, 55, 74, 74)), with: upDown(night, 18, 92))
            shiningBall = Path(ellipseIn: centred(50, 55, 74, 74)).strokedPath(StrokeStyle(lineWidth: 3.4 * u))

        case .android:
            // A head shaped like ours, in the robot's pale shell: round ear
            // pieces, a line across the brow and a small light on the forehead.
            for x in [15.0, 85.0] {
                g.fill(Path(ellipseIn: centred(x, 57, 13, 15)), with: .color(shellLow))
                g.fill(Path(ellipseIn: centred(x, 57, 5.5, 5.5)), with: .color(light.opacity(0.9)))
            }
            g.fill(Path(roundedRect: rect(18, 15, 64, 79), cornerRadius: 31 * u, style: .continuous),
                   with: upDown([shellTop, shellLow], 15, 94))
            var seam = Path()
            seam.move(to: point(21, 40))
            seam.addQuadCurve(to: point(79, 40), control: point(50, 29))
            g.stroke(seam, with: .color(shellLow.opacity(0.9)), lineWidth: 0.9 * u)
            shiningBall = pill(centred(50, 26.5, 9, 3.4))
            g.fill(pill(centred(50, 26.5, 9, 3.4)), with: .color(light))

        case .bellhop:
            // A cartoon person in a concierge's small round hat.
            let skin = [Color(red: 0.99, green: 0.86, blue: 0.75), Color(red: 0.95, green: 0.76, blue: 0.64)]
            g.fill(Path(ellipseIn: centred(50, 50, 74, 70)), with: .color(hair))
            for x in [17.0, 83.0] {
                g.fill(Path(ellipseIn: centred(x, 60, 9, 12)), with: .color(skin[1]))
            }
            g.fill(Path(roundedRect: rect(19, 24, 62, 71), cornerRadius: 30 * u, style: .continuous),
                   with: upDown(skin, 24, 95))
            var fringe = Path()
            fringe.move(to: point(17.5, 54))
            fringe.addQuadCurve(to: point(50, 20), control: point(16, 21))
            fringe.addQuadCurve(to: point(82.5, 54), control: point(84, 21))
            fringe.addQuadCurve(to: point(60, 36), control: point(80, 38))
            fringe.addQuadCurve(to: point(17.5, 54), control: point(30, 38))
            g.fill(fringe, with: .color(hair))
            cap(59, 17, turn: 11)

        case .owl:
            // A round brown owl: two ear tufts, a pale disc around each eye.
            let feathers = [Color(red: 0.66, green: 0.50, blue: 0.38), Color(red: 0.48, green: 0.35, blue: 0.27)]
            for flip in [1.0, -1.0] {
                func mirrored(_ x: Double, _ y: Double) -> CGPoint { point(50 - flip * (50 - x), y) }
                var tuft = Path()
                tuft.move(to: mirrored(15, 46))
                tuft.addLine(to: mirrored(16, 17))
                tuft.addLine(to: mirrored(40, 28))
                tuft.closeSubpath()
                g.fill(tuft, with: .color(feathers[0]))
                g.stroke(tuft, with: .color(feathers[0]), style: StrokeStyle(lineWidth: 5 * u, lineJoin: .round))
            }
            g.fill(Path(roundedRect: rect(12, 24, 76, 69), cornerRadius: 33 * u, style: .continuous),
                   with: upDown(feathers, 24, 93))
            for x in [35.0, 65.0] {
                g.fill(Path(ellipseIn: centred(x, 53, 31, 33)), with: .color(Color(red: 0.98, green: 0.93, blue: 0.83)))
            }
            cap(50, 16, turn: -7)

        case .penguin:
            // A penguin: dark head, white face, a bow tie under the chin.
            g.fill(Path(roundedRect: rect(12, 21, 76, 70), cornerRadius: 34 * u, style: .continuous),
                   with: upDown([Color(red: 0.22, green: 0.27, blue: 0.41), Color(red: 0.11, green: 0.13, blue: 0.23)], 21, 91))
            let white = Color(red: 0.97, green: 0.98, blue: 1.0)
            for x in [36.5, 63.5] {
                g.fill(Path(ellipseIn: centred(x, 53, 33, 35)), with: .color(white))
            }
            g.fill(Path(ellipseIn: centred(50, 68, 54, 38)), with: .color(white))
            for flip in [1.0, -1.0] {
                var wing = Path()
                wing.move(to: point(50, 93))
                wing.addLine(to: point(50 + flip * 10, 88.5))
                wing.addLine(to: point(50 + flip * 10, 97.5))
                wing.closeSubpath()
                g.fill(wing, with: .color(light))
                g.stroke(wing, with: .color(light), style: StrokeStyle(lineWidth: 1.6 * u, lineJoin: .round))
            }
            g.fill(Path(ellipseIn: centred(50, 93, 5, 5)), with: .color(tint(-0.2)))
            cap(57, 15, turn: 10)

        case .pup:
            // A golden puppy: floppy ears, a pale muzzle, a dark nose.
            let ear = Color(red: 0.74, green: 0.52, blue: 0.31)
            for (x, turn) in [(15.0, 10.0), (85.0, -10.0)] {
                var flap = g
                flap.translateBy(x: x * u, y: 52 * u)
                flap.rotate(by: .degrees(turn + sin(time * 1.3) * 1.5))
                flap.fill(Path(roundedRect: CGRect(x: -10 * u, y: -24 * u, width: 20 * u, height: 48 * u), cornerRadius: 10 * u),
                          with: .color(ear))
            }
            g.fill(Path(roundedRect: rect(17, 21, 66, 71), cornerRadius: 30 * u, style: .continuous),
                   with: upDown([Color(red: 0.97, green: 0.82, blue: 0.58), Color(red: 0.91, green: 0.71, blue: 0.46)], 21, 92))
            g.fill(Path(ellipseIn: centred(50, 72, 40, 30)), with: .color(Color(red: 1.0, green: 0.95, blue: 0.87)))
            g.fill(Path(roundedRect: centred(50, 64.5, 12, 8), cornerRadius: 3.6 * u), with: .color(hair))
            g.fill(Path(ellipseIn: centred(48, 63, 3.4, 1.8)), with: .color(Color.white.opacity(0.5)))
            g.stroke(Path { p in p.move(to: point(50, 68.5)); p.addLine(to: point(50, 73)) },
                     with: .color(hair), style: StrokeStyle(lineWidth: 1.6 * u, lineCap: .round))
            cap(57, 16, turn: 10)
        }

        let roam = Face.gaze(at: time)
        let dx = (pose.lookX + pose.wander * roam.x) * 3.6
        let dy = (pose.lookY + pose.wander * roam.y) * 2.6
        let open = Face.blink(at: time)
        let eyes = [36.0 + dx, 64.0 + dx], eyeY = plan.eyeY + dy

        // Pink cheeks.
        for x in [26.5, 73.5] {
            let cx = x + dx * 0.4, cy = plan.cheekY + dy * 0.4
            g.fill(Path(ellipseIn: centred(cx, cy, 11, 7)), with: .radialGradient(
                Gradient(colors: [pink.opacity(plan.darkInk ? 0.8 : 0.62), pink.opacity(0)]),
                center: point(cx, cy), startRadius: 0, endRadius: 5.4 * u))
        }

        // Eyes and mouth, and whatever else shines.
        let mouth = mouthOpening
        let mouthX = 50 + dx * 0.5, mouthY = plan.mouthY + dy * 0.5
        let eyeWidth = pose.eyeWidth, eyeHeight = pose.eyeHeight, closed = pose.closed
        let smile = pose.smile, wave = pose.wave, glow = pose.glow, darkInk = plan.darkInk
        let eyeKind = plan.eyes, beak = plan.beak
        g.drawLayer { layer in
            if !darkInk {
                layer.addFilter(.shadow(color: light.opacity(0.85 * glow), radius: 2.6 * u))
            }
            if let shiningBall {
                layer.fill(shiningBall, with: .color(light.opacity(0.55 + 0.45 * pulse)))
            }
            let height = max(eyeHeight * open * (1 - closed), 1.6)
            for cx in eyes {
                switch eyeKind {
                case .solid:
                    layer.fill(pill(centred(cx, eyeY, eyeWidth, height)), with: .color(ink.opacity(1 - closed)))
                case .iris:
                    layer.fill(pill(centred(cx, eyeY, eyeWidth, height)), with: .color(ink.opacity(1 - closed)))
                    let ring = min(eyeWidth * 0.62, height * 0.8)
                    layer.stroke(Path(ellipseIn: centred(cx, eyeY, ring, ring)), with: .color(light.opacity(1 - closed)),
                                 lineWidth: min(1.7, height * 0.2) * u)
                case .person:
                    // The white stays nearly put; the pupil does the looking.
                    let white = cx - dx * 0.7
                    layer.fill(pill(centred(white, eyeY, eyeWidth, height)), with: .color(Color.white.opacity(1 - closed)))
                    let pupil = min(eyeWidth * 0.66, height)
                    layer.fill(Path(ellipseIn: centred(white + dx * 0.55, eyeY + dy * 0.2, pupil, pupil)),
                               with: .color(ink.opacity(1 - closed)))
                }
                if closed > 0.01 {
                    // Asleep: each eye is a small contented arc.
                    var lid = Path()
                    let half = eyeWidth * 0.55
                    lid.move(to: point(cx - half, eyeY))
                    lid.addQuadCurve(to: point(cx + half, eyeY), control: point(cx, eyeY + 5.5 * closed))
                    layer.stroke(lid, with: .color(ink.opacity(closed)),
                                 style: StrokeStyle(lineWidth: 2.3 * u, lineCap: .round))
                }
            }
            // The closed mouth: a small curve, up for a smile.
            let closedMouth = beak ? 0 : (1 - mouth.weight) * (1 - wave)
            if closedMouth > 0.01 {
                var curve = Path()
                let lift = smile * 1.2
                curve.move(to: point(mouthX - 5.5, mouthY - lift))
                curve.addQuadCurve(to: point(mouthX + 5.5, mouthY - lift),
                                   control: point(mouthX, mouthY - lift + smile * 6.5))
                layer.stroke(curve, with: .color(ink.opacity(closedMouth)),
                             style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
            }
            if mouth.weight > 0.01, !beak {
                layer.fill(pill(centred(mouthX, mouthY + 0.5, mouth.width, mouth.height)),
                           with: .color(ink.opacity(mouth.weight)))
            }
            // Thinking: three dots that bob in turn.
            if wave > 0.01 {
                for i in -1...1 {
                    let swell = sin(time * 7 - Double(i) * 1.1)
                    layer.fill(Path(ellipseIn: centred(mouthX + Double(i) * 5.2, mouthY + (beak ? 10 : 0) + swell * 1.5, 2.8, 2.8)),
                               with: .color(ink.opacity(wave * (0.7 + 0.3 * swell))))
                }
            }
        }

        if plan.beak {
            // The beak: the lower half drops with the voice.
            let drop = mouth.weight * (mouth.height - 2.2) * 0.75
            var lower = Path()
            lower.move(to: point(mouthX - 3.6, mouthY))
            lower.addLine(to: point(mouthX + 3.6, mouthY))
            lower.addLine(to: point(mouthX, mouthY + 3 + drop))
            lower.closeSubpath()
            let dark = Color(red: 0.86, green: 0.44, blue: 0.12)
            g.fill(lower, with: .color(dark))
            g.stroke(lower, with: .color(dark), style: StrokeStyle(lineWidth: 1.6 * u, lineJoin: .round))
            var upper = Path()
            upper.move(to: point(mouthX - 5.2, mouthY - 1.5))
            upper.addQuadCurve(to: point(mouthX + 5.2, mouthY - 1.5), control: point(mouthX, mouthY - 6))
            upper.addLine(to: point(mouthX, mouthY + 3.6))
            upper.closeSubpath()
            let orange = Color(red: 0.99, green: 0.68, blue: 0.22)
            g.fill(upper, with: .color(orange))
            g.stroke(upper, with: .color(orange), style: StrokeStyle(lineWidth: 1.6 * u, lineJoin: .round))
        }
        if plan.human || plan.brows {
            // Eyebrows: up with wide eyes, slanted with worry, one up while it thinks.
            let worry = max(0, -pose.smile)
            for (i, cx) in eyes.enumerated() {
                let inward = i == 0 ? 1.0 : -1.0
                let lift = (pose.eyeHeight - 14.5) * 0.6 + (i == 1 ? pose.wave * 2.6 : 0) - pose.closed * 1.5
                let y = eyeY - pose.eyeHeight / 2 - 4.2 - lift
                var brow = Path()
                brow.move(to: point(cx - inward * 5.2, y + 0.8 + worry * 1.2))
                brow.addQuadCurve(to: point(cx + inward * 5.2, y + 0.4 - worry * 2.8), control: point(cx, y - 1.6))
                g.stroke(brow, with: .color(ink.opacity(style == .android ? 0.55 : 0.95)),
                         style: StrokeStyle(lineWidth: 1.9 * u, lineCap: .round))
            }
        }
        if plan.human {
            // A small nose.
            var nose = Path()
            nose.move(to: point(mouthX - 1.6, plan.cheekY - 1.2))
            nose.addQuadCurve(to: point(mouthX + 1.6, plan.cheekY - 1.2), control: point(mouthX, plan.cheekY + 1.2))
            g.stroke(nose, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1.4 * u, lineCap: .round))
        }

        // A sparkle in each open eye.
        let sparkle = (1 - pose.closed) * min(1, max(0, (open - 0.5) * 2))
        for base in eyes {
            let cx = plan.eyes == .person ? base - dx * 0.15 : base
            let w = pose.eyeWidth, h = pose.eyeHeight
            g.fill(Path(ellipseIn: centred(cx - w * 0.17, eyeY - h * 0.2, w * 0.3, w * 0.3)),
                   with: .color(Color.white.opacity(0.95 * sparkle)))
            g.fill(Path(ellipseIn: centred(cx + w * 0.2, eyeY + h * 0.2, w * 0.14, w * 0.14)),
                   with: .color(Color.white.opacity(0.7 * sparkle)))
        }
        if style == .robot {
            g.fill(Path(ellipseIn: centred(48.6, 8, 2.2, 2.2)), with: .color(Color.white.opacity(0.7)))
        }
        if pose.wave > 0.01 {
            // While it thinks, a spark circles: the antenna's ball, the leaves, or the whole ring.
            let a = time * 5
            let orbit = style == .halo ? (x: 50.0, y: 55.0, radius: 37.0) : plan.spark
            g.fill(Path(ellipseIn: centred(orbit.x + cos(a) * orbit.radius, orbit.y + sin(a) * orbit.radius, 2.6, 2.6)),
                   with: .color((style == .halo ? Color.white : light).opacity(pose.wave)))
        }

        // Asleep: small letters drift up from it. Drawn as lines: text of a
        // new size for every picture is slow to lay out.
        if pose.closed > 0.05 {
            for k in 0..<2 {
                let phase = (time * 0.22 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let size = 3.4 + phase * 2.8
                let x = plan.sleep.x + phase * 12, y = plan.sleep.y - phase * 12
                var z = Path()
                z.move(to: point(x, y))
                z.addLine(to: point(x + size, y))
                z.addLine(to: point(x, y + size))
                z.addLine(to: point(x + size, y + size))
                g.stroke(z, with: .color(light.opacity(pose.closed * sin(.pi * phase))),
                         style: StrokeStyle(lineWidth: size * 0.3 * u, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
