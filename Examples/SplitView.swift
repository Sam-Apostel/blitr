import SwiftUI

// A two-column NavigationSplitView: sidebar and detail side by side on iPad, one stack on iPhone.

struct Mail: View {
    let folders = ["Inbox", "Drafts", "Sent", "Archive", "Trash"]

    var body: some View {
        NavigationSplitView {
            List(folders, id: \.self) { folder in
                Label(folder, systemImage: "tray")
            }
            .navigationTitle("Mailboxes")
        } detail: {
            VStack(spacing: 8) {
                Image(systemName: "envelope").font(.largeTitle).foregroundStyle(.secondary)
                Text("No Message Selected").font(.title3.weight(.semibold))
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview { Mail() }
