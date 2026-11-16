import Foundation
func describe(_ a: AttributedString) -> String {
    var out = String(a.characters).debugDescription + " |"
    for run in a.runs {
        let kinds = run.presentationIntent?.components.map { c -> String in
            switch c.kind { case .paragraph: "p"; case .header(let l): "h\(l)"; case .unorderedList: "ul"; case .orderedList: "ol"
            case .listItem(let o): "li\(o)"; case .blockQuote: "q"; default: "?" } }.joined(separator: ">") ?? "-"
        out += " [\(String(a[run.range].characters).debugDescription) i=\(run.inlinePresentationIntent?.rawValue ?? 0) \(kinds)]"
    }
    return out
}
let inputs = ["# Header\n\nA *paragraph* line.\n\n- First item\n- Second **item**", "line one\nline two", "line one  \nline two",
  "> quoted\n\npara", "1. one\n2. two", "a\n\nb", "## Title\nbody", "- a\n- b\n\n1. c\n2. d", "Plain **bold** [link](https://x.y)",
  "* star\n+ plus", "text\n- item"]
var bad = 0
for src in inputs {
    let apple = describe(try! AttributedString(markdown: src, options: .init(interpretedSyntax: .full)))
    let ours = describe(MarkdownInline.parseBlocks(src, baseURL: nil))
    if apple != ours { bad += 1; print("DIFF", src.debugDescription, "\n  apple:", apple, "\n  ours: ", ours) }
}
print("mismatches:", bad, "of", inputs.count)
if bad > 0 { exit(1) }
