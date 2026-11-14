import SwiftUI

// Text(AttributedString): Markdown's inline presentation intents (bold, italic, code, strikethrough) and links,
// SwiftUI's attribute scope (font, colors, underline, strikethrough, kerning, tracking, baseline offset)
// set on the whole string, on ranges found through the runs, and through an AttributeContainer.

struct AttributedTextExample: View {
    private var markdown: AttributedString {
        (try? AttributedString(markdown: "Plain, **bold**, _italic_, `code`, ~~struck~~ and a [link](https://example.com)."))
            ?? AttributedString()
    }

    /// The strongly emphasized runs restyled: heavier font, white on a dark background.
    private var restyled: AttributedString {
        var a = (try? AttributedString(markdown: "Leave **now** for the _ferry_ at **9:40**")) ?? AttributedString()
        let bold = a.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }.map(\.range)
        for r in bold {
            a[r].font = .body.weight(.heavy)
            a[r].foregroundColor = .white
        }
        return a
    }

    private var styled: AttributedString {
        var a = AttributedString("Underlined title")
        a.font = .title3
        a.underlineStyle = .single
        var tail = AttributedString(" was €40")
        tail.strikethroughStyle = Text.LineStyle(pattern: .solid, color: .red)
        tail.foregroundColor = .secondary
        a.append(tail)
        return a
    }

    private var container: AttributedString {
        var c = AttributeContainer()
        c.foregroundColor = .red
        c.backgroundColor = .yellow
        var a = AttributedString("Highlighted", attributes: c)
        var spaced = AttributedString(" wide")
        spaced.kern = 4
        var tracked = AttributedString(" tracked")
        tracked.tracking = 2
        var raised = AttributedString(" up")
        raised.baselineOffset = 6
        raised.font = .caption
        a += spaced + tracked + raised
        return a
    }

    private var full: AttributedString {
        (try? AttributedString(markdown: "# Header\n\nA *paragraph* line.\n\n- First item\n- Second **item**",
                               options: .init(interpretedSyntax: .full))) ?? AttributedString()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(markdown)
            Text(restyled)
                .padding(8)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
            Text(styled)
            Text(container)
            Text(full)
            Text(AttributedString(localized: "Localized with **strong** and *emphasis*."))
            Text(markdown).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    AttributedTextExample()
}
