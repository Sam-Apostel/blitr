import SwiftUI

// A foldable's hinge (iOS 27.1): closed, partly open like a book, or flat open. Render with
// --device iphone-duo, iphone-duo-half-open or iphone-duo-open; elsewhere there is no hinge.

struct HingeReadout: View {
    @State private var status = "Waiting"
    @State private var degrees: Double?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.system(size: 48))
            Text(status).font(.title.bold())
            if let degrees {
                Text("\(Int(degrees.rounded()))°")
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HingeTracking(status: $status, degrees: $degrees))
    }
}

/// `onHingeChange` and its types are iOS 27.1 and later.
struct HingeTracking: ViewModifier {
    @Binding var status: String
    @Binding var degrees: Double?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                guard let hinge = new.hinge else { status = "No hinge"; degrees = nil; return }
                status = hinge.status == .partiallyOpen ? "Partly open" : hinge.status == .fullyOpen ? "Open" : "Closed"
                degrees = hinge.angle.degrees
            }
        } else {
            content
        }
    }
}

#Preview {
    HingeReadout()
}
