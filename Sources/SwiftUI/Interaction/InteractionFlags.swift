// The runner's capture flags (`--steps`, `--frames`, `--animated`, ...). See docs/INTERACTION.md.

@MainActor
enum InteractionFlags {
    /// `--date` was given (otherwise a capture uses `CaptureClock.defaultDate`).
    static var dateWasSet = false

    /// Handles `flag` if it is a capture flag; `value` consumes its argument. False for other flags.
    static func parse(_ flag: String, value: () -> String) throws -> Bool {
        func number(_ range: ClosedRange<Double>) throws -> Double {
            let raw = value()
            guard let v = Double(raw), range.contains(v) else {
                throw RenderError("\(flag) takes a number in \(AnimationDefaults.format(range.lowerBound))...\(AnimationDefaults.format(range.upperBound)), not \"\(raw)\"")
            }
            return v
        }
        switch flag {
        case "--steps":
            let n = InteractionSession.request.scripts.count + 1
            InteractionSession.request.scripts.append((value(), n == 1 ? "--steps" : "--steps[\(n)]"))
        case "--steps-file":
            let path = value()
            guard let data = FileManager.default.contents(atPath: path) else { throw RenderError("--steps-file: cannot read \(path)") }
            InteractionSession.request.scripts.append((String(decoding: data, as: UTF8.self), path))
        case "--frames": InteractionSession.request.framesDirectory = value()
        case "--frames-every-step": InteractionSession.request.framesEveryStep = true
        case "--frames-all": InteractionSession.request.framesAll = true
        case "--filmstrip": InteractionSession.request.filmstripPath = value()
        case "--filmstrip-frames": InteractionSession.request.filmstripFrames = Int(try number(1...200))
        case "--filmstrip-scale": InteractionSession.request.filmstripScale = try number(0.05...1)
        case "--animated": InteractionSession.request.animatedPath = value()
        case "--animated-scale": InteractionSession.request.animatedScale = try number(0.05...1)
        case "--fps": InteractionSession.request.fps = Int(try number(1...120))
        case "--duration": InteractionSession.request.duration = try number(0...120)
        case "--hold": InteractionSession.request.hold = try number(0...30)
        case "--animate-all": InteractionSession.request.animateAll = true
        case "--full-content": InteractionSession.request.fullContentPath = value()
        case "--gif-dither": InteractionSession.request.gif.dither = true
        case "--gif-palette":
            let raw = value()
            guard raw == "global" || raw == "local" else { throw RenderError("--gif-palette takes global or local") }
            InteractionSession.request.gif.localPalettes = raw == "local"
        case "--date":
            let raw = value()
            guard let date = InteractionDates.parse(raw) else {
                throw RenderError("--date takes an ISO 8601 date such as 2025-06-01T09:41:00Z, not \"\(raw)\"")
            }
            Runtime.referenceDate = date
            dateWasSet = true
        default:
            return false
        }
        return true
    }
}
