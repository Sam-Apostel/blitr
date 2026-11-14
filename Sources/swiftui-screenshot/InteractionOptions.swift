import Foundation

// The interaction and animation capture flags of `render`: `--steps`, `--steps-file`, `--frames`,
// `--filmstrip`, `--animated`, `--duration`, `--date` and their options. The runner does the work
// (Sources/SwiftUI/Interaction, Sources/SwiftUI/Animation, docs/INTERACTION.md); this file parses the
// flags and derives one output name per image like the PNG names.

struct InteractionCLIOptions {
    /// Flags passed through as they are, in order.
    var passthrough: [String] = []
    var framesDirectory: String?
    var filmstripPath: String?
    var animatedPath: String?
    var fullContentPath: String?

    static let valueFlags: Set<String> = ["--steps", "--steps-file", "--frames", "--filmstrip", "--filmstrip-frames", "--filmstrip-scale",
                                          "--animated", "--animated-scale", "--fps", "--duration", "--hold", "--full-content",
                                          "--gif-palette", "--date"]
    static let plainFlags: Set<String> = ["--frames-every-step", "--frames-all", "--animate-all", "--gif-dither"]

    static let usage = """
          --steps "<script>"     Actions applied in order after the first frame, separated by `;` (repeatable):
                                 tap, type, submit, set, select-tab, scroll, scroll-to, swipe, long-press, dismiss,
                                 back, press, wait, snapshot. Selectors: "label", an accessibility identifier,
                                 #index, @x,y. The PNG shows the state after the last step. See docs/INTERACTION.md
          --steps-file <file>    The same, one step per line, `# comments` allowed
          --frames <dir>         Write a PNG for every `snapshot` step
          --frames-every-step    ...and one after every step
          --frames-all           ...and every in-between frame of animations
          --filmstrip <file.png> The frames side by side with the step as caption (animations: evenly spaced frames)
          --filmstrip-frames <n> Number of evenly spaced frames in the filmstrip
          --filmstrip-scale <f>  Size of filmstrip frames relative to the render (default: 2 pixels per point)
          --animated <file>      Animated capture; the extension picks the format: .gif, .png (APNG, lossless),
                                 .webp (lossless), .mp4 / .mov (needs ffmpeg on PATH)
          --animated-scale <f>   Size relative to the render (default: 1 pixel per point)
          --fps <n>              Frames per second of animations (default 30)
          --duration <s>         Capture this many seconds of time-driven content (TimelineView(.animation),
                                 PhaseAnimator, KeyframeAnimator, spinners) before the first step
          --hold <s>             Seconds each settled state is shown in animated outputs (default 0.6)
          --animate-all          Animate every step's change with the default animation, not only withAnimation
          --gif-palette <p>      global (default) | local: one palette per frame
          --gif-dither           Ordered dithering in GIFs
          --full-content <file.png>  One tall PNG of the first scroll view's whole content, bars drawn once
          --date <ISO8601>       Fix "now" for TimelineView and Text(date, style:) (a capture without it uses a fixed date)
    """

    var isActive: Bool { !passthrough.isEmpty || framesDirectory != nil || filmstripPath != nil || animatedPath != nil || fullContentPath != nil }

    /// Records `flag`; false when it is not one of ours. `value` consumes the flag's argument.
    mutating func record(_ flag: String, value: () -> String) -> Bool {
        if InteractionCLIOptions.plainFlags.contains(flag) {
            passthrough.append(flag)
            return true
        }
        guard InteractionCLIOptions.valueFlags.contains(flag) else { return false }
        let v = value()
        switch flag {
        case "--frames": framesDirectory = v
        case "--filmstrip": filmstripPath = v
        case "--animated": animatedPath = v
        case "--full-content": fullContentPath = v
        case "--steps-file": passthrough += [flag, (v as NSString).isAbsolutePath ? v : FileManager.default.currentDirectoryPath + "/" + v]
        default: passthrough += [flag, v]
        }
        return true
    }

    /// `base` with the image's name suffix inserted before the extension (see AccessibilityCLIOptions).
    private func derive(_ base: String, png: String, stem: String, multiple: Bool, outDir: String?) -> String {
        guard multiple else { return base }
        let pngStem = ((png as NSString).lastPathComponent as NSString).deletingPathExtension
        let suffix = pngStem.hasPrefix(stem) ? String(pngStem.dropFirst(stem.count)) : "-" + pngStem
        let ns = base as NSString
        let name = (ns.lastPathComponent as NSString).deletingPathExtension + suffix + (ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension)
        let dir = ns.deletingLastPathComponent
        return (dir.isEmpty ? (outDir ?? ".") : dir) + "/" + name
    }

    func arguments(png: String, stem: String, multiple: Bool, outDir: String?) -> [String] {
        var args = passthrough
        if let framesDirectory { args += ["--frames", derive(framesDirectory, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if let filmstripPath { args += ["--filmstrip", derive(filmstripPath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if let animatedPath { args += ["--animated", derive(animatedPath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if let fullContentPath { args += ["--full-content", derive(fullContentPath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        return args
    }

    /// Text-mode report after one image: the files written (the step log itself comes on stderr).
    func report(_ runnerLine: String, json: Bool) {
        guard isActive, !json, let data = runnerLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let frames = object["frames"] as? [String], !frames.isEmpty {
            print("  frames: \(frames.count) in \((frames[0] as NSString).deletingLastPathComponent)")
        }
        if let path = object["filmstrip"] as? String { print("  filmstrip: \(path)") }
        if let path = object["animated"] as? String {
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
            let dims = (object["animatedSize"] as? [Int]).map { "\($0[0])x\($0[1]), " } ?? ""
            print("  animated: \(path)  (\(dims)\(object["animatedFrames"] ?? "?") frames, \(object["captureDuration"] ?? "?")s, \(size / 1024) KB)")
        }
        if let path = object["fullContent"] as? String { print("  full content: \(path)") }
    }
}
