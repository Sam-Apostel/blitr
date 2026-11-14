import SwiftUI

// A medium-detent sheet with a grabber over a list, which itself presents an alert.
// (Change the detents to [.large] to see the pushed-back presenter.)

struct Inbox: View {
    @State private var showsCompose = true
    var body: some View {
        List {
            Section("Mailboxes") {
                Text("All Inboxes").badge(4)
                Text("VIP")
                Text("Flagged")
            }
            Section {
                ForEach(0..<10) { i in Text("Message \(i + 1)") }
            }
        }
        .sheet(isPresented: $showsCompose) {
            List {
                Section("Draft") {
                    Text("To: team@example.com")
                    Text("Subject: Weekly update")
                }
            }
            .presentationDetents([.medium, .large])
            .alert(isPresented: .constant(true)) {
                Alert(title: Text("Discard Draft?"), message: Text("Your changes will be lost."),
                      primaryButton: .destructive(Text("Discard")), secondaryButton: .cancel())
            }
        }
    }
}

#Preview { Inbox() }
