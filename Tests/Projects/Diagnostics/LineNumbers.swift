import SwiftUI

// This file does not compile, on purpose: Tests/Projects/run.sh checks that the error is reported on
// its real line (27), although the rewrites above it (a multi-line #Preview argument list and an
// @Entry declaration) change the text the compiler sees.

extension EnvironmentValues {
    @Entry var orchardRowHeight: CGFloat = 44
    @Entry var orchardCaption: String? = nil
}

struct LineNumbersView: View {
    @Environment(\.orchardRowHeight) private var rowHeight

    var body: some View {
        Text("Row").frame(height: rowHeight)
    }
}

#Preview(
    "Line numbers",
    traits: .sizeThatFitsLayout
) {
    LineNumbersView()
}

let deliberatelyWrong: Int = "the compiler must report this on line 27"
