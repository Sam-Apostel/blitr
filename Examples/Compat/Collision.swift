import SwiftUI

struct V: View {
    @State private var a = "a0"
    @State private var b = "b0"
    @Environment(\.horizontalSizeClass) private var h
    @Environment(\.verticalSizeClass) private var v
    var body: some View {
        VStack {
            Text(a); Text(b); Text("\(String(describing: h)) \(String(describing: v))")
        }
        .onAppear { a = "a1" }
        .onAppear { b = "b1" }
    }
}
#Preview { V() }
