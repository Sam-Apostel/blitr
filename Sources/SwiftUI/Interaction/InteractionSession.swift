// An interaction capture: scripted steps after the first frame, in-between frames of animations, and
// the frame, filmstrip and animated outputs (docs/INTERACTION.md).
//
// `Renderer.render` starts a session when a capture flag was given, calls `passWillBegin` /
// `passDidLayout` from its pass loop, and hands over once the first frame is drawn (`run`). The session
// then drives the same pass loop and the same drawing through `RenderHost`. Time only moves by the
// frame interval (`CaptureClock`): nothing here reads a wall clock.

struct InteractionRequest {
    var scripts: [(text: String, source: String)] = []
    var framesDirectory: String?
    var framesEveryStep = false
    var framesAll = false
    var filmstripPath: String?
    var filmstripFrames: Int?
    var filmstripScale: Double?
    var animatedPath: String?
    var animatedScale: Double?
    var fps = 30
    var duration: Double?
    var animateAll = false
    /// Seconds a settled state is held in animated outputs.
    var hold = 0.6
    var gif = GIFOptions()
    var fullContentPath: String?

    var isActive: Bool {
        !scripts.isEmpty || framesDirectory != nil || filmstripPath != nil || animatedPath != nil || duration != nil || fullContentPath != nil
    }
}

@MainActor
struct RenderHost {
    let runtime: Runtime
    /// Runs resolve/layout passes until the state is quiet.
    let settle: () -> Void
    let root: () -> Node
    /// Clears the surface and draws the current tree with device chrome.
    let draw: () -> Void
    let surface: OpaquePointer
    let canvasSize: () -> CGSize
    let scale: CGFloat
    let colorScheme: () -> ColorScheme
    let environment: () -> EnvironmentValues
    let background: RGBA
}

@MainActor
final class InteractionSession {
    static var request = InteractionRequest()
    static var current: InteractionSession?
    /// Merged into the runner's JSON result line.
    static var payload: [String: Any] = [:]

    let request: InteractionRequest
    let runtime: Runtime
    private var steps: [Step] = []

    /// The tree of the latest pass, and the one before the first animated transaction of the first frame.
    private var lastTree: Node?
    private var initialBefore: Node?
    private var initialTransaction: Transaction?

    private var host: RenderHost!
    private var timeline: [TimedFrame] = []
    private var timelineCaptions: [String] = []
    private var stripCells: [(image: FrameImage, caption: String)] = []
    private var writtenFrames: [String] = []
    private var frameNumber = 0
    private var elapsed = 0.0
    private var explicitSnapshots = false
    private var sizeWarned = false

    private init(request: InteractionRequest, runtime: Runtime) {
        self.request = request
        self.runtime = runtime
    }

    static func begin(runtime: Runtime) throws -> InteractionSession? {
        payload = [:]
        guard request.isActive else { return nil }
        let session = InteractionSession(request: request, runtime: runtime)
        for script in request.scripts {
            do { session.steps += try StepScript.parse(script.text, source: script.source) }
            catch let error as StepScriptError { throw RenderError(error.description) }
        }
        if let path = request.animatedPath {
            let ext = (path as NSString).pathExtension.lowercased()
            guard AnimatedOutput.extensions.contains(ext) else {
                throw RenderError("--animated \(path): unknown format \".\(ext)\". Use .png (APNG), .gif, .webp, .mp4 or .mov")
            }
            if ext == "mp4" || ext == "mov", AnimatedOutput.findExecutable("ffmpeg") == nil {
                throw RenderError("--animated \(path): .mp4 and .mov need ffmpeg, which is not on PATH. Install ffmpeg, or use .gif, .png (APNG) or .webp, which are written without it.")
            }
        }
        guard request.fps >= 1, request.fps <= 120 else { throw RenderError("--fps takes 1...120") }
        session.explicitSnapshots = session.steps.contains { if case .snapshot = $0.action { return true }; return false }
        CaptureInfo.isRecording = true
        TransactionRecorder.isRecording = true
        _ = TransactionRecorder.take()
        InteractionRegistry.isActive = true
        CaptureClock.isActive = true
        CaptureClock.time = 0
        ClockTriggers.reset()
        if !InteractionFlags.dateWasSet { Runtime.referenceDate = CaptureClock.defaultDate }
        current = session
        return session
    }

    static func end() {
        current = nil
        CaptureInfo.isRecording = false
        TransactionRecorder.isRecording = false
        InteractionRegistry.isActive = false
        CaptureClock.isActive = false
        CaptureClock.time = 0
        Tweener.active = nil
    }

    // MARK: Pass loop hooks

    func passWillBegin() {
        InteractionRegistry.beginPass()
        CaptureClock.wasRead = false
    }

    func passDidLayout(_ root: Node) {
        // A transaction recorded since the last pass changed the state that pass showed.
        if host == nil, initialBefore == nil, let first = TransactionRecorder.recorded.first(where: { $0.animation != nil }) {
            initialBefore = lastTree
            initialTransaction = first
        }
        lastTree = root
    }

    // MARK: Frames

    private var frameInterval: Double { 1.0 / Double(request.fps) }
    private var wantsEvenFilmstrip: Bool {
        request.filmstripPath != nil && (request.filmstripFrames != nil || steps.isEmpty)
    }
    /// Every frame of the capture is needed (not only the settled states).
    private var needsTimeline: Bool { request.animatedPath != nil || request.framesAll || wantsEvenFilmstrip }
    private var timelineScale: Double {
        if request.animatedPath != nil { return request.animatedScale ?? 1.0 / Double(host.scale) }
        return filmstripScale
    }
    private var filmstripScale: Double { request.filmstripScale ?? min(1, 2.0 / Double(host.scale)) }

    enum FrameKind { case start, step, tween, snapshot }

    private func slug(_ text: String) -> String {
        var s = ""
        for c in text.lowercased() {
            if c.isLetter || c.isNumber { s.append(c) } else if s.last != "-" { s.append("-") }
            if s.count >= 40 { break }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Records what is on the surface as a frame shown for `seconds`.
    private func emit(_ kind: FrameKind, caption: String, seconds: Double, name: String? = nil) throws {
        frameNumber += 1
        elapsed += seconds
        if let directory = request.framesDirectory {
            let wanted: Bool
            switch kind {
            case .snapshot: wanted = true
            case .start, .step: wanted = request.framesEveryStep || request.framesAll
            case .tween: wanted = request.framesAll
            }
            if wanted {
                let label = slug(name ?? caption)
                let path = directory + "/" + String(format: "%03d", writtenFrames.count + 1) + (label.isEmpty ? "" : "-" + label) + ".png"
                try FramePixels.writePNG(surface: host.surface, to: path)
                writtenFrames.append(path)
            }
        }
        let ms = max(1, Int((seconds * 1000).rounded()))
        if request.animatedPath != nil || wantsEvenFilmstrip {
            let image = try FramePixels.grab(surface: host.surface, factor: timelineScale)
            if let last = timeline.last, last.image.isIdentical(to: image) {
                timeline[timeline.count - 1].milliseconds += ms
            } else {
                timeline.append(TimedFrame(image: image, milliseconds: ms))
                timelineCaptions.append(caption)
            }
        }
        if request.filmstripPath != nil, !wantsEvenFilmstrip {
            let wanted = explicitSnapshots ? kind == .snapshot : (kind == .start || kind == .step)
            if wanted { stripCells.append((try FramePixels.grab(surface: host.surface, factor: filmstripScale), name ?? caption)) }
        }
    }

    private func drawPlain() {
        Tweener.active = nil
        host.draw()
    }

    /// Holds the current state for `seconds`; time-driven content keeps moving.
    private func hold(_ kind: FrameKind, caption: String, seconds: Double, name: String? = nil) throws {
        guard seconds > 0 else { return }
        if CaptureClock.wasRead && needsTimeline {
            let count = max(1, Int((seconds * Double(request.fps)).rounded()))
            for k in 0..<count {
                if k > 0 {
                    CaptureClock.time += frameInterval
                    host.settle()
                }
                drawPlain()
                try emit(k == 0 ? kind : .tween, caption: caption, seconds: frameInterval, name: k == 0 ? name : nil)
            }
            CaptureClock.time += frameInterval
            host.settle()
        } else {
            drawPlain()
            try emit(kind, caption: caption, seconds: seconds, name: name)
            CaptureClock.time += seconds
            if CaptureClock.wasRead { host.settle() }
        }
    }

    /// Plays the change from `before` to the current tree. Returns a description for the log.
    private func play(from before: Node, transaction: Transaction, minimum: Double = 0) throws -> (frames: Int, note: String) {
        var tween = Tweener(before: before, after: host.root(), transaction: transaction)
        guard tween.hasChanges else { return (0, "no visible change") }
        let span = max(tween.duration, minimum)
        guard needsTimeline, tween.duration > 0 else {
            return (0, tween.duration > 0 ? "state changed (\(describe(tween)))" : "state changed")
        }
        let count = max(1, Int((span * Double(request.fps) - 1e-9).rounded(.up)))
        let note = "state changed, \(count) frames (\(describe(tween)))"
        for k in 1...count {
            CaptureClock.time += frameInterval
            if CaptureClock.wasRead {
                host.settle()
                tween = Tweener(before: before, after: host.root(), transaction: transaction)
            }
            let t = Double(k) * frameInterval
            if tween.endsAtTarget && t >= tween.duration - 1e-9 {
                // Settled: exactly what a plain render of the new state draws.
                drawPlain()
            } else {
                tween.time = t
                Tweener.active = tween
                host.draw()
                Tweener.active = nil
            }
            // The caller holds (and emits) the settled last frame.
            if k < count || !tween.endsAtTarget { try emit(.tween, caption: "", seconds: frameInterval) }
        }
        return (count, note)
    }

    private func describe(_ tween: Tweener) -> String {
        let names = tween.animationsUsed.map { $0.description }
        let d = AnimationDefaults.format((tween.duration * 100).rounded() / 100)
        return names.isEmpty ? "\(d)s" : names.joined(separator: ", ") + ", \(d)s"
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func checkSize() {
        guard !sizeWarned else { return }
        let size = host.canvasSize()
        if abs(size.width - initialSize.width) > 0.5 || abs(size.height - initialSize.height) > 0.5 {
            sizeWarned = true
            runtime.warn("The view changed size during the capture (\(Int(initialSize.width))x\(Int(initialSize.height)) to \(Int(size.width))x\(Int(size.height)) points); frames keep the size of the first one. Use the device layout or --layout fixed for captures.")
        }
    }
    private var initialSize = CGSize.zero

    // MARK: Running

    func run(_ host: RenderHost) throws {
        self.host = host
        initialSize = host.canvasSize()
        Tweener.canvasBackground = host.background.a > 0 ? host.background : SystemColor.background.resolve(host.colorScheme())
        if let directory = request.framesDirectory {
            do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) }
            catch { throw RenderError("--frames: cannot create \(directory): \(error.localizedDescription)") }
        }
        _ = TransactionRecorder.take()

        // The first frame. An animation started while it appeared (withAnimation in onAppear) plays from
        // the state before it.
        var opening = request.duration ?? 0
        if let before = initialBefore, let transaction = initialTransaction, needsTimeline {
            let probe = Tweener(before: before, after: host.root(), transaction: transaction)
            if probe.hasChanges, probe.duration > 0 {
                probe.time = 0
                Tweener.active = probe
                host.draw()
                Tweener.active = nil
                try emit(.start, caption: "start", seconds: frameInterval)
                let result = try play(from: before, transaction: transaction, minimum: opening - frameInterval)
                log("start -> \(result.note)")
                opening = 0
                if probe.endsAtTarget { try hold(.tween, caption: "start", seconds: steps.isEmpty ? frameInterval : request.hold) }
            }
        }
        if frameNumber == 0 {
            let seconds = opening > 0 ? opening : (steps.isEmpty ? frameInterval : request.hold)
            try hold(.start, caption: "start", seconds: seconds)
        }

        for (number, step) in steps.enumerated() {
            try perform(step, number: number + 1)
            checkSize()
        }

        drawPlain()
        try finish()
    }

    private func perform(_ step: Step, number: Int) throws {
        let prefix = "\(step.source):\(step.line): \(step.text)"
        switch step.action {
        case .wait(let seconds):
            try hold(.tween, caption: step.text, seconds: seconds)
            log("\(step.text) -> \(AnimationDefaults.format(seconds))s")
            return
        case .snapshot(let name):
            drawPlain()
            try emit(.snapshot, caption: name ?? "snapshot \(number)", seconds: frameInterval, name: name)
            log("\(step.text) -> frame \(frameNumber)")
            return
        default: break
        }

        let before = host.root()
        _ = TransactionRecorder.take()
        InteractionRegistry.passCount = 0
        let index = ElementIndex(root: before, screen: CGRect(origin: .zero, size: host.canvasSize()), runtime: runtime)
        let outcome = try act(step.action, index: index, step: prefix)
        if let scroll = outcome.scroll, needsTimeline {
            let frames = try playScroll(scroll)
            try hold(.step, caption: step.text, seconds: request.hold)
            log("\(step.text) -> \(outcome.note), \(frames) frames")
            return
        }
        if let scroll = outcome.scroll { runtime.focus.scrollOffsets[scroll.path] = scroll.target }
        runtime.needsAnotherPass = true
        host.settle()
        let recorded = TransactionRecorder.take()
        var transaction = recorded.transactions.first { $0.animation != nil } ?? Transaction(animation: request.animateAll ? .default : nil)
        if recorded.transactions.contains(where: { $0.disablesAnimations }) { transaction.disablesAnimations = true }
        let passes = InteractionRegistry.passCount
        let result = try play(from: before, transaction: transaction)
        if !recorded.completions.isEmpty {
            for completion in recorded.completions { completion() }
            host.settle()
        }
        try hold(.step, caption: step.text, seconds: request.hold)
        var line = "\(step.text) -> "
        if !outcome.note.isEmpty { line += outcome.note + "; " }
        line += "\(result.note), \(passes) pass\(passes == 1 ? "" : "es")"
        log(line)
    }

    // MARK: Scrolling

    struct ScrollRequest {
        var path: IdentityPath
        var start: CGPoint
        var target: CGPoint
    }

    /// Scrolls with UIScrollView's deceleration: the offset is laid out anew for every frame, so bars,
    /// pinned headers and lazy rows behave as they do at that offset.
    private func playScroll(_ scroll: ScrollRequest) throws -> Int {
        let distance = hypot(scroll.target.x - scroll.start.x, scroll.target.y - scroll.start.y)
        guard distance > 0.5 else { return 0 }
        let duration = SystemTransitions.scrollDuration
        let count = max(1, Int((duration * Double(request.fps)).rounded(.up)))
        let k = -1000 * Foundation.log(SystemTransitions.scrollRate)
        let total = 1 - exp(-k * duration)
        for i in 1...count {
            let t = Double(i) * frameInterval
            let p = i == count ? 1 : (1 - exp(-k * t)) / total
            runtime.focus.scrollOffsets[scroll.path] = CGPoint(x: scroll.start.x + (scroll.target.x - scroll.start.x) * CGFloat(p),
                                                               y: scroll.start.y + (scroll.target.y - scroll.start.y) * CGFloat(p))
            CaptureClock.time += frameInterval
            runtime.needsAnotherPass = true
            host.settle()
            drawPlain()
            if i < count { try emit(.tween, caption: "", seconds: frameInterval) }
        }
        return count
    }

    // MARK: Actions

    struct Outcome {
        var note = ""
        var scroll: ScrollRequest?
    }

    private func describe(_ e: InteractionElement) -> String {
        e.label.isEmpty ? "#\(e.index) \(e.role)" : "\(e.role) \"\(e.label)\""
    }

    private func act(_ action: StepAction, index: ElementIndex, step: String) throws -> Outcome {
        var outcome = Outcome()
        switch action {
        case .tap(let selector, let half):
            let e = try index.resolve(selector, step: step)
            let stepper = index.handlers(for: e) { $0.increment != nil || $0.decrement != nil }
            var side = half
            if side == nil, let stepper, stepper.kind == "stepper" {
                // A point inside the control picks the half under it.
                if case .point(let p) = selector, p.x > e.frame.maxX - 94 {
                    side = p.x > e.frame.maxX - 47 ? .increment : .decrement
                } else {
                    throw RenderError("\(step): \(describe(e)) is a stepper; say which half: `tap \(selector) +` or `tap \(selector) -` (or `set \(selector) <value>`)")
                }
            }
            if let side {
                guard let stepper else { throw RenderError("\(step): \(describe(e)) is not a stepper or slider; + and - only apply to those") }
                guard let run = side == .increment ? stepper.increment : stepper.decrement else {
                    throw RenderError("\(step): \(describe(e)) cannot be \(side == .increment ? "incremented" : "decremented")")
                }
                run()
                outcome.note = side == .increment ? "incremented" : "decremented"
                return outcome
            }
            if e.ax.activate == nil, index.handlers(for: e, where: { $0.kind == "slider" }) != nil {
                throw RenderError("\(step): \(describe(e)) is a slider; use `set \(selector) <value>` (or `tap \(selector) +` / `-` for one step)")
            }
            if let text = index.handlers(for: e, where: { $0.setText != nil }), e.ax.activate == nil {
                // A text field takes focus; the keyboard is not drawn.
                _ = text
                if let f = runtime.focus.snapshot.elements.first(where: { $0.frame.intersects(e.frame) && ["textField", "secureField", "textEditor"].contains($0.role) }) {
                    runtime.focus.requestedPath = f.path
                }
                outcome.note = "focused \(describe(e)) (the keyboard is not drawn; use `type` to enter text)"
                return outcome
            }
            if e.ax.activate == nil, let picker = index.handlers(for: e, where: { $0.kind == "picker" && $0.setValue != nil }), e.role == "picker" {
                _ = picker
                throw RenderError("\(step): \(describe(e)) opens a menu, which is not drawn. Choose an option with `set \(selector) <option>`")
            }
            if e.ax.activate == nil, let settable = index.handlers(for: e, where: { $0.setValue != nil && $0.kind != "toggle" && $0.kind != "picker" }) {
                throw RenderError("\(step): tapping \(describe(e)) opens a \(settable.kind) editor, which is not drawn. Use `set \(selector) <value>`")
            }
            guard let tap = index.tapAction(e) else {
                throw RenderError("\(step): \(describe(e)) has no action the capture can run (gestures attached with .gesture() and custom controls are not simulated; onTapGesture and the built-in controls are)")
            }
            switch tap {
            case .run(let run):
                run()
                outcome.note = "activated \(describe(e))"
            case .back:
                try goBack(step: step)
                outcome.note = "went back"
            }
        case .type(let selector, let text, let submit):
            let e = try index.resolve(selector, step: step)
            guard let h = index.handlers(for: e, where: { $0.setText != nil }) else {
                throw RenderError("\(step): \(describe(e)) is not a text field bound to a String (fields with value:format: cannot be typed into)")
            }
            h.setText?(text)
            outcome.note = "typed into \(describe(e))"
            if submit {
                h.submit?()
                outcome.note += ", submitted"
            }
        case .submit(let selector):
            let e = try index.resolve(selector, step: step)
            guard let h = index.handlers(for: e, where: { $0.submit != nil }) else {
                throw RenderError("\(step): \(describe(e)) is not a text field")
            }
            h.submit?()
            outcome.note = "submitted \(describe(e))"
        case .set(let selector, let value):
            let e = try index.resolve(selector, step: step)
            guard let h = index.handlers(for: e, where: { $0.setValue != nil }) else {
                if index.handlers(for: e, where: { $0.setText != nil }) != nil {
                    throw RenderError("\(step): \(describe(e)) is a text field; use `type \(selector) \"\(value)\"`")
                }
                throw RenderError("\(step): \(describe(e)) has no value to set (set works on sliders, steppers, pickers, toggles and date pickers)")
            }
            do { outcome.note = "set \(describe(e)) to \(try h.setValue!(value))" }
            catch let error as RenderError { throw RenderError("\(step): \(error.description)") }
        case .selectTab(let name):
            outcome.note = try selectTab(name, index: index, step: step)
        case .scroll(let selector, let dx, let dy):
            let target: ElementIndex.Scrollable
            if selector == .first {
                guard let first = index.scrollables().first else { throw RenderError("\(step): there is no scroll view, List or Form on screen") }
                target = first
            } else {
                let e = try index.resolve(selector, step: step, interactiveOnly: false)
                guard let around = index.scrollable(around: e.frame) else { throw RenderError("\(step): \(describe(e)) is not inside a scroll view") }
                target = around
            }
            outcome = scroll(target, by: CGPoint(x: dx, y: dy))
        case .scrollTo(let selector):
            let e = try index.resolve(selector, step: step, interactiveOnly: false)
            guard let around = index.scrollable(around: e.frame) else { throw RenderError("\(step): \(describe(e)) is not inside a scroll view") }
            let margin: CGFloat = 16
            var d = CGPoint.zero
            let v = around.viewport, f = e.frame
            if f.minY < v.minY + margin { d.y = f.minY - (v.minY + margin) } else if f.maxY > v.maxY - margin { d.y = f.maxY - (v.maxY - margin) }
            if around.axes.contains(.horizontal) {
                if f.minX < v.minX + margin { d.x = f.minX - (v.minX + margin) } else if f.maxX > v.maxX - margin { d.x = f.maxX - (v.maxX - margin) }
            }
            outcome = scroll(around, by: d)
            outcome.note = "scrolled to \(describe(e)): " + outcome.note
        case .swipe(let selector, let direction, let name):
            guard direction == .left || direction == .right else {
                throw RenderError("\(step): vertical swipes scroll; use `scroll <selector> <dy>`")
            }
            let e = try index.resolve(selector, step: step, interactiveOnly: false)
            // Swiping left reveals the trailing actions, right the leading ones.
            if let h = index.handlers(for: e, where: { direction == .left ? !$0.swipeTrailing.isEmpty : !$0.swipeLeading.isEmpty }) {
                let actions = direction == .left ? h.swipeTrailing : h.swipeLeading
                var chosen = actions[0]
                if let name {
                    guard let match = actions.first(where: { $0.label.caseInsensitiveCompare(name) == .orderedSame })
                        ?? actions.first(where: { $0.label.range(of: name, options: .caseInsensitive) != nil }) else {
                        throw RenderError("\(step): no swipe action \"\(name)\" on \(describe(e)). Actions: \(actions.map { "\"\($0.label)\"" }.joined(separator: ", "))")
                    }
                    chosen = match
                }
                chosen.run()
                outcome.note = "ran swipe action \"\(chosen.label)\" of \(describe(e)) (the revealed buttons are not drawn)"
            } else if let pager = InteractionRegistry.pagers.last(where: { CGRect(origin: $0.node.absoluteOrigin, size: $0.node.frame.size).intersects(e.frame) }) {
                let next = pager.selected + (direction == .left ? 1 : -1)
                guard next >= 0, next < pager.count else {
                    throw RenderError("\(step): the paging TabView is on its \(direction == .left ? "last" : "first") page")
                }
                pager.select(next)
                outcome.note = "paged to page \(next + 1) of \(pager.count)"
            } else {
                throw RenderError("\(step): \(describe(e)) has no \(direction == .left ? "trailing" : "leading") swipe actions (.swipeActions, ForEach.onDelete) and is not in a paging TabView")
            }
        case .longPress(let selector):
            let e = try index.resolve(selector, step: step, interactiveOnly: false)
            if let h = index.handlers(for: e, where: { $0.longPress != nil }) {
                h.longPress?()
                outcome.note = "long-pressed \(describe(e))"
            } else if index.handlers(for: e, where: { $0.hasContextMenu }) != nil {
                throw RenderError("\(step): \(describe(e)) has a context menu, which the renderer cannot show; context menus are not simulated")
            } else {
                throw RenderError("\(step): \(describe(e)) has no onLongPressGesture action")
            }
        case .dismiss:
            if let dismiss = runtime.focus.snapshot.dismissTop {
                dismiss()
                outcome.note = "dismissed the \(runtime.focus.snapshot.modalKind ?? "presentation")"
            } else {
                do { try goBack(step: step) } catch {
                    throw RenderError("\(step): nothing is presented and no screen is pushed")
                }
                outcome.note = "went back"
            }
        case .back:
            try goBack(step: step)
            outcome.note = "went back"
        case .press(let press):
            let result = runtime.focus.press(press, runtime: runtime)
            outcome.note = result.note
        case .wait, .snapshot:
            break
        }
        return outcome
    }

    private func scroll(_ target: ElementIndex.Scrollable, by d: CGPoint) -> Outcome {
        let start = runtime.focus.scrollOffsets[target.path] ?? .zero
        let end = CGPoint(x: min(max(0, start.x + (target.axes.contains(.horizontal) ? d.x : 0)), target.maxOffset.x),
                          y: min(max(0, start.y + (target.axes.contains(.vertical) ? d.y : 0)), target.maxOffset.y))
        var outcome = Outcome()
        outcome.scroll = ScrollRequest(path: target.path, start: start, target: end)
        let moved = CGPoint(x: end.x - start.x, y: end.y - start.y)
        outcome.note = "scrolled by \(Int(moved.y.rounded()))" + (moved.x != 0 ? ",\(Int(moved.x.rounded()))" : "") + "pt to offset \(Int(end.y.rounded()))"
        if abs(moved.y - d.y) > 0.5 || abs(moved.x - d.x) > 0.5 { outcome.note += " (clamped to the content)" }
        return outcome
    }

    /// Pops the top screen of the innermost navigation stack that has one.
    func goBack(step: String) throws {
        for stack in InteractionRegistry.stacks.reversed() {
            if var pushes = runtime.focus.pushes[stack.path], !pushes.isEmpty {
                pushes.removeLast()
                runtime.focus.pushes[stack.path] = pushes
                runtime.needsAnotherPass = true
                return
            }
            if let pop = InteractionRegistry.pathPops[stack.path], pop() {
                runtime.needsAnotherPass = true
                return
            }
        }
        throw RenderError("\(step): there is no pushed screen to go back from (screens shown with the deprecated NavigationLink(isActive:) forms cannot be popped)")
    }

    /// `@Environment(\.dismiss)` called by user code: the topmost presentation, else the top pushed screen.
    func dismissFromEnvironment() {
        if let dismiss = runtime.focus.snapshot.dismissTop {
            dismiss()
            runtime.needsAnotherPass = true
        } else {
            try? goBack(step: "dismiss()")
        }
    }

    private func selectTab(_ name: String, index: ElementIndex, step: String) throws -> String {
        func find(_ node: Node) -> TabViewNode? {
            if let host = node as? PresentationHostNode, let top = host.layers.last { return find(top) }
            if let tabs = node as? TabViewNode { return tabs }
            for child in node.children { if let t = find(child) { return t } }
            return nil
        }
        guard let tabs = find(index.root), let select = tabs.selectTab else {
            throw RenderError("\(step): there is no TabView with a tab bar on screen")
        }
        let labels: [String] = tabs.items.map { item in
            var parts: [AXLabelPart] = []
            if let title = item.title { axLabelParts(title, into: &parts, geometry: false) }
            if parts.isEmpty, let icon = item.icon { axLabelParts(icon, into: &parts, geometry: false) }
            return parts.map(\.text).joined(separator: ", ")
        }
        var chosen = labels.firstIndex(of: name) ?? labels.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        if chosen == nil {
            let partial = labels.indices.filter { labels[$0].range(of: name, options: .caseInsensitive) != nil }
            if partial.count == 1 { chosen = partial[0] }
        }
        if chosen == nil, let n = Int(name.hasPrefix("#") ? String(name.dropFirst()) : name), labels.indices.contains(n - 1) { chosen = n - 1 }
        guard let chosen else {
            throw RenderError("\(step): no tab \"\(name)\". Tabs: \(labels.enumerated().map { "\($0.offset + 1): \"\($0.element)\"" }.joined(separator: ", "))")
        }
        select(chosen)
        return "selected tab \(chosen + 1) \"\(labels[chosen])\""
    }

    // MARK: Outputs

    private func finish() throws {
        var payload: [String: Any] = ["frameCount": frameNumber, "captureDuration": (elapsed * 1000).rounded() / 1000]
        if request.framesDirectory != nil { payload["frames"] = writtenFrames }
        if let path = request.animatedPath {
            try AnimatedOutput.write(timeline, to: path, fps: request.fps, gif: request.gif)
            payload["animated"] = path
            payload["animatedFrames"] = timeline.count
            if let first = timeline.first { payload["animatedSize"] = [first.image.width, first.image.height] }
        }
        if let path = request.filmstripPath {
            var cells = stripCells
            if wantsEvenFilmstrip {
                cells = []
                let wanted = max(1, request.filmstripFrames ?? 6)
                let total = timeline.reduce(0) { $0 + $1.milliseconds }
                // Evenly spaced moments, first and last included.
                var starts: [Int] = []
                var t = 0
                for frame in timeline { starts.append(t); t += frame.milliseconds }
                for i in 0..<wanted {
                    let moment = wanted == 1 ? 0 : Int((Double(total - 1) * Double(i) / Double(wanted - 1)).rounded())
                    let frame = starts.lastIndex { $0 <= moment } ?? 0
                    cells.append((timeline[frame].image, AnimationDefaults.format((Double(moment) / 10).rounded() / 100) + "s"))
                }
            }
            guard !cells.isEmpty else { throw RenderError("--filmstrip: the capture has no frames") }
            let pixelsPerPoint = Double(host.scale) * (wantsEvenFilmstrip ? timelineScale : filmstripScale)
            try Filmstrip.compose(cells, pixelsPerPoint: pixelsPerPoint, scheme: host.colorScheme(), environment: host.environment(),
                                  runtime: runtime, to: path)
            payload["filmstrip"] = path
        }
        if let path = request.fullContentPath {
            try FullContent.render(host: host, to: path)
            payload["fullContent"] = path
        }
        InteractionSession.payload = payload
    }
}
