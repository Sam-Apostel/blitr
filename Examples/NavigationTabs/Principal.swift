import SwiftUI

#Preview {
    NavigationStack {
        Text("Principal item replaces title")
            .navigationTitle("Hidden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Custom").font(.headline)
                        Text("subtitle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) { Image(systemName: "gear") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Image(systemName: "square.and.arrow.up")
                    Image(systemName: "ellipsis.circle")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Image(systemName: "folder")
                    Spacer()
                    Text("12 items").font(.caption)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                }
            }
    }
}
