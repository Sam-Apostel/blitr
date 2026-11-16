// The step script of `--steps` / `--steps-file` (grammar in docs/INTERACTION.md).
//
// One step per line; on a command line steps are separated by `;`. A `#` followed by a space (or at the
// end of a line) starts a comment; `#3` is a selector. Strings are quoted with " or ' and may hold
// `\"`, `\\`, `\n`. Unknown steps and malformed arguments are errors.

enum StepAction: Equatable {
    case tap(Selector, half: StepperHalf?)
    case type(Selector, String, submit: Bool)
    case submit(Selector)
    case set(Selector, String)
    case selectTab(String)
    case scroll(Selector, dx: CGFloat, dy: CGFloat)
    case scrollTo(Selector)
    case swipe(Selector, SwipeDirection, action: String?)
    case longPress(Selector)
    case dismiss
    case back
    case shake
    case press(RemotePress)
    case wait(Double)
    case snapshot(String?)

    enum StepperHalf: Equatable { case increment, decrement }
    enum SwipeDirection: String, Equatable { case left, right, up, down }
}

struct Step {
    var action: StepAction
    /// The step as written (the caption of its frame and the head of its log line).
    var text: String
    var line: Int
    var source: String
}

struct StepScriptError: Error, CustomStringConvertible {
    var description: String
}

enum StepScript {
    static let verbs = ["tap", "type", "submit", "set", "select-tab", "scroll", "scroll-to", "swipe", "long-press",
                        "dismiss", "back", "shake", "press", "wait", "snapshot"]

    static let summary = """
    Steps:
      tap <selector> [+|-]          activate an element (+/-: a stepper's halves)
      type <selector> "text" [submit]   set a text field's text (submit: also run onSubmit)
      submit <selector>             run a text field's onSubmit
      set <selector> <value>        slider, stepper, picker, toggle (on/off), date picker (ISO 8601)
      select-tab <name|index>
      scroll <selector|first> <dy> [dx]   scroll a scroll view by points (positive dy moves the content up)
      scroll-to <selector>
      swipe <selector> left|right [action]   run a row's swipe action; page a paging TabView
      long-press <selector>
      dismiss | back
      shake                         shake the device (UIKit's motionBegan/motionEnded on the key window)
      press up|down|left|right|select|menu|playpause
      wait <seconds>
      snapshot [name]
    Selectors: "label" (exact, then part of it), an accessibility identifier, #index, @x,y, "label"[n]
    """

    /// Splits into tokens: bare words and quoted strings (flagged). `;` and newlines end a step.
    private struct Token { var text: String; var quoted: Bool }

    static func parse(_ script: String, source: String) throws -> [Step] {
        var steps: [Step] = []
        var line = 1
        var tokens: [Token] = []
        var raw = ""
        var startLine = 1
        // Windows line endings are one Character in Swift ("\r\n"): normalize first.
        let chars = Array(script.replacingOccurrences(of: "\r\n", with: "\n"))
        let separators: Set<Character> = [" ", "\t", "\r", "\n", ";"]
        var i = 0

        func fail(_ message: String, _ l: Int) -> StepScriptError {
            StepScriptError(description: "\(source):\(l): \(message)")
        }
        func flush() throws {
            defer { tokens = []; raw = "" }
            guard !tokens.isEmpty else { return }
            let text = raw.trimmingCharacters(in: .whitespaces)
            steps.append(Step(action: try action(tokens, text: text, fail: { fail($0, startLine) }), text: text, line: startLine, source: source))
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" || c == ";" {
                try flush()
                if c == "\n" { line += 1 }
                i += 1
                continue
            }
            if c == " " || c == "\t" || c == "\r" {
                raw.append(c)
                i += 1
                continue
            }
            // A comment: `#` at the start of a token, followed by whitespace or the end of the line.
            if c == "#", i + 1 >= chars.count || chars[i + 1] == " " || chars[i + 1] == "\t" || chars[i + 1] == "\n" || chars[i + 1] == "#" || chars[i + 1] == "!" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if tokens.isEmpty { startLine = line }
            if c == "\"" || c == "'" {
                let quote = c
                var value = ""
                var closed = false
                raw.append(c)
                i += 1
                while i < chars.count {
                    let d = chars[i]
                    raw.append(d)
                    if d == "\\", i + 1 < chars.count {
                        let e = chars[i + 1]
                        raw.append(e)
                        switch e {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        default: value.append(e)
                        }
                        i += 2
                        continue
                    }
                    if d == quote { closed = true; i += 1; break }
                    if d == "\n" { line += 1 }
                    value.append(d)
                    i += 1
                }
                guard closed else { throw fail("unterminated string starting with \(quote)\(value.prefix(20))", startLine) }
                // `"Delete"[2]`: the index suffix belongs to the string.
                var token = Token(text: value, quoted: true)
                if i < chars.count, chars[i] == "[" {
                    var suffix = ""
                    while i < chars.count, !separators.contains(chars[i]) { suffix.append(chars[i]); raw.append(chars[i]); i += 1 }
                    token.text += "\u{0}" + suffix
                }
                tokens.append(token)
                continue
            }
            var word = ""
            while i < chars.count, !separators.contains(chars[i]) {
                word.append(chars[i])
                i += 1
            }
            raw += word
            tokens.append(Token(text: word, quoted: false))
        }
        try flush()
        return steps
    }

    private static func selector(_ token: Token, fail: (String) -> StepScriptError) throws -> Selector {
        var text = token.text
        var nth: Int?
        if token.quoted, let split = text.firstIndex(of: "\u{0}") {
            let suffix = String(text[text.index(after: split)...])
            text = String(text[..<split])
            guard suffix.hasPrefix("["), suffix.hasSuffix("]"), let n = Int(suffix.dropFirst().dropLast()), n >= 1 else {
                throw fail("expected \"label\"[n] with n >= 1, found \(suffix) after \"\(text)\"")
            }
            nth = n
        }
        if token.quoted { return .text(text, nth: nth) }
        if text == "first" { return .first }
        if text.hasPrefix("#") {
            guard let n = Int(text.dropFirst()), n >= 1 else { throw fail("\"\(text)\" is not an element index; write #1, #2, ...") }
            return .index(n)
        }
        if text.hasPrefix("@") {
            let parts = text.dropFirst().split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
                throw fail("\"\(text)\" is not a point; write @x,y in points, e.g. @120,400")
            }
            return .point(CGPoint(x: x, y: y))
        }
        if text.hasPrefix("id:") { return .text(String(text.dropFirst(3)), nth: nil) }
        if let open = text.lastIndex(of: "["), text.hasSuffix("]"), let n = Int(text[text.index(after: open)...].dropLast()), n >= 1 {
            return .text(String(text[..<open]), nth: n)
        }
        return .text(text, nth: nil)
    }

    private static func action(_ tokens: [Token], text: String, fail: (String) -> StepScriptError) throws -> StepAction {
        let verb = tokens[0].text.lowercased()
        let args = Array(tokens.dropFirst())
        func need(_ n: ClosedRange<Int>, _ usage: String) throws {
            guard n.contains(args.count) else { throw fail("`\(text)`: expected `\(usage)`") }
        }
        func number(_ t: Token, _ what: String) throws -> Double {
            guard let v = Double(t.text) else { throw fail("`\(text)`: \(what) must be a number, not \"\(t.text)\"") }
            return v
        }
        guard !tokens[0].quoted else { throw fail("a step starts with a verb, not a string: `\(text)`") }
        switch verb {
        case "tap":
            try need(1...2, "tap <selector> [+|-]")
            var half: StepAction.StepperHalf?
            if args.count == 2 {
                switch args[1].text.lowercased() {
                case "+", "increment", "plus": half = .increment
                case "-", "decrement", "minus": half = .decrement
                default: throw fail("`\(text)`: after the selector only + or - (a stepper's halves) may follow")
                }
            }
            return .tap(try selector(args[0], fail: fail), half: half)
        case "type":
            try need(2...3, "type <selector> \"text\" [submit]")
            if args.count == 3, args[2].text.lowercased() != "submit" { throw fail("`\(text)`: the only word allowed after the text is `submit`") }
            return .type(try selector(args[0], fail: fail), args[1].text, submit: args.count == 3)
        case "submit":
            try need(1...1, "submit <selector>")
            return .submit(try selector(args[0], fail: fail))
        case "set":
            guard args.count >= 2 else { throw fail("`\(text)`: expected `set <selector> <value>`") }
            return .set(try selector(args[0], fail: fail), args.dropFirst().map(\.text).joined(separator: " "))
        case "select-tab", "selecttab", "tab":
            try need(1...1, "select-tab <name|index>")
            return .selectTab(args[0].text)
        case "scroll":
            try need(2...3, "scroll <selector|first> <dy> [dx]")
            return .scroll(try selector(args[0], fail: fail), dx: args.count == 3 ? CGFloat(try number(args[2], "dx")) : 0,
                           dy: CGFloat(try number(args[1], "dy")))
        case "scroll-to", "scrollto":
            try need(1...1, "scroll-to <selector>")
            return .scrollTo(try selector(args[0], fail: fail))
        case "swipe":
            try need(2...3, "swipe <selector> left|right [action]")
            guard let direction = StepAction.SwipeDirection(rawValue: args[1].text.lowercased()) else {
                throw fail("`\(text)`: the direction must be left, right, up or down")
            }
            return .swipe(try selector(args[0], fail: fail), direction, action: args.count == 3 ? args[2].text : nil)
        case "long-press", "longpress":
            try need(1...1, "long-press <selector>")
            return .longPress(try selector(args[0], fail: fail))
        case "dismiss":
            try need(0...0, "dismiss")
            return .dismiss
        case "back":
            try need(0...0, "back")
            return .back
        case "shake":
            try need(0...0, "shake")
            return .shake
        case "press":
            try need(1...1, "press up|down|left|right|select|menu|playpause")
            guard let press = RemotePress(argument: args[0].text) else {
                throw fail("`\(text)`: unknown remote key \"\(args[0].text)\"; use \(RemotePress.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return .press(press)
        case "wait":
            try need(1...1, "wait <seconds>")
            let s = try number(args[0], "the duration")
            guard s >= 0, s <= 60 else { throw fail("`\(text)`: wait takes 0...60 seconds") }
            return .wait(s)
        case "snapshot":
            try need(0...1, "snapshot [name]")
            return .snapshot(args.first?.text)
        default:
            let close = verbs.min { distance($0, verb) < distance($1, verb) }
            let hint = close.flatMap { distance($0, verb) <= 3 ? " Did you mean `\($0)`?" : nil } ?? ""
            throw fail("unknown step `\(tokens[0].text)`.\(hint)\n\(summary)")
        }
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var row = Array(0...y.count)
        for i in 1...max(1, x.count) where i <= x.count {
            var previous = row[0]
            row[0] = i
            for j in 1...max(1, y.count) where j <= y.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (x[i - 1] == y[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[y.count]
    }
}
