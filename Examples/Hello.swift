import SwiftUI

struct ProfileCard: View {
    @State private var following = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .overlay(Text("SA").font(.title3).fontWeight(.semibold).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sam Apostel").font(.headline)
                    Text("Building a **SwiftUI** renderer for _Linux_")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("This card was laid out and rasterized on a headless Linux box. No simulator, no macOS, no browser.")
                .font(.body)
            HStack {
                ForEach(["Layout", "Text", "Shapes"], id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
                Spacer()
                Text(following ? "Following" : "Follow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.blue, in: Capsule())
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .padding(20)
    }
}

#Preview {
    ZStack {
        Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea()
        ProfileCard()
    }
}
