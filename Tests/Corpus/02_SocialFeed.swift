import SwiftUI
import Observation

// MARK: - Model

struct FeedPost: Identifiable, Hashable {
    let id = UUID()
    let author: String
    let handle: String
    let time: String
    let body: String
    let colors: [Color]
    let aspect: CGFloat
    var likes: Int
    var comments: Int
    var shares: Int
    var liked = false
}

@Observable
final class FeedViewModel {
    var posts: [FeedPost] = []
    var isLoading = false

    func load() async {
        guard posts.isEmpty else { return }
        isLoading = true
        posts = FeedViewModel.sample
        isLoading = false
    }

    func toggleLike(_ post: FeedPost) {
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[i].liked.toggle()
        posts[i].likes += posts[i].liked ? 1 : -1
    }

    static let sample: [FeedPost] = [
        FeedPost(author: "Maya Chen", handle: "@maya", time: "2m",
                 body: "Golden hour over the ridge this evening. Hiked four miles for this view and it was absolutely worth every step.",
                 colors: [.orange, .pink, .purple], aspect: 4.0 / 3.0, likes: 128, comments: 14, shares: 6),
        FeedPost(author: "Jon Alvarez", handle: "@jonny", time: "37m",
                 body: "Shipped the new onboarding flow today. Small team, big feeling. Thanks to everyone who tested the beta builds!",
                 colors: [.teal, .blue], aspect: 16.0 / 9.0, likes: 84, comments: 22, shares: 3),
        FeedPost(author: "Priya Nair", handle: "@priya", time: "2h",
                 body: "Reading list for the long weekend:\n1. Designing Data-Intensive Applications\n2. The Pragmatic Programmer\n3. Something with dragons",
                 colors: [.green, .mint, .yellow], aspect: 1, likes: 301, comments: 48, shares: 19),
    ]
}

// MARK: - Subviews

struct FeedAvatar: View {
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

struct FeedActionButton: View {
    let symbol: String
    let count: Int
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("\(count)", systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

struct FeedPostCard: View {
    let post: FeedPost
    let onLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FeedAvatar(name: post.author)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author).font(.headline)
                    Text("\(post.handle) · \(post.time)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            }
            Text(post.body)
                .font(.body)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            LinearGradient(colors: post.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .aspectRatio(post.aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "photo")
                        .padding(8)
                        .foregroundStyle(.white.opacity(0.8))
                }

            HStack(spacing: 24) {
                FeedActionButton(symbol: post.liked ? "heart.fill" : "heart", count: post.likes,
                                 tint: post.liked ? .red : .secondary, action: onLike)
                    .sensoryFeedback(.selection, trigger: post.liked)
                    .accessibilityLabel("Like, \(post.likes) likes")
                FeedActionButton(symbol: "bubble.right", count: post.comments) {}
                    .accessibilityLabel("Comment, \(post.comments) comments")
                FeedActionButton(symbol: "arrowshape.turn.up.right", count: post.shares) {}
                    .accessibilityLabel("Share, \(post.shares) shares")
                Spacer()
                Image(systemName: "bookmark").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

// MARK: - Screen

struct SocialFeedScreen: View {
    @State private var model = FeedViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(model.posts) { post in
                        FeedPostCard(post: post) {
                            withAnimation(.spring(duration: 0.3)) { model.toggleLike(post) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.gray.opacity(0.12))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Menu")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search")
                    Button { } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Compose")
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }
}

#Preview {
    SocialFeedScreen()
}

#Preview("Dark") {
    SocialFeedScreen().preferredColorScheme(.dark)
}
