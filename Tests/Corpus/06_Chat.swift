import SwiftUI

// MARK: - Model (ObservableObject style)

struct ChatMessage: Identifiable, Equatable {
    enum Sender { case me, them }
    let id = UUID()
    let sender: Sender
    let text: String
    let time: String
}

enum ChatItem: Identifiable {
    case separator(String)
    case message(ChatMessage)
    case typing

    var id: String {
        switch self {
        case .separator(let title): return "sep-\(title)"
        case .message(let message): return message.id.uuidString
        case .typing: return "typing"
        }
    }
}

final class ChatViewModel: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var draft = ""

    func load() {
        guard items.isEmpty else { return }
        items = [
            .separator("Yesterday"),
            .message(ChatMessage(sender: .them, text: "Hey! Are we still on for the climbing gym tomorrow?", time: "18:02")),
            .message(ChatMessage(sender: .me, text: "Yes! 6pm works for me.", time: "18:05")),
            .separator("Today"),
            .message(ChatMessage(sender: .them, text: "Perfect. I booked the 6pm slot for both of us, and I will bring the extra chalk bag so you do not have to buy one.", time: "09:41")),
            .message(ChatMessage(sender: .me, text: "You are the best", time: "09:44")),
            .message(ChatMessage(sender: .me, text: "Want to grab ramen afterwards?", time: "09:44")),
            .typing,
        ]
    }

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.removeAll { if case .typing = $0 { return true } else { return false } }
        items.append(.message(ChatMessage(sender: .me, text: trimmed, time: "09:46")))
        items.append(.typing)
        draft = ""
    }
}

// MARK: - Subviews

struct ChatBubble: View {
    let message: ChatMessage
    private var isMe: Bool { message.sender == .me }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 48) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(isMe ? Color.white : Color.primary)
                    .background(isMe ? Color.blue : Color.gray.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 280, alignment: isMe ? .trailing : .leading)
                Text(message.time).font(.caption2).foregroundStyle(.secondary)
            }
            if !isMe { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChatTypingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(phase ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.2), in: Capsule())
            Spacer()
        }
        .onAppear { phase = true }
        .accessibilityLabel("Typing")
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Attach")
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit(onSend)
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(text.isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Screen

struct ChatScreen: View {
    @StateObject private var model = ChatViewModel()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.items) { item in
                            switch item {
                            case .separator(let title):
                                Text(title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            case .message(let message):
                                ChatBubble(message: message)
                            case .typing:
                                ChatTypingIndicator()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onChange(of: model.items.count) {
                    if let last = model.items.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ChatInputBar(text: $model.draft) { model.send() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                            .frame(width: 30, height: 30)
                            .overlay(Text("AK").font(.caption.bold()).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Alex Kim").font(.subheadline.weight(.semibold))
                            Text("online").font(.caption2).foregroundStyle(.green)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "video") }
                        .accessibilityLabel("Video call")
                }
            }
            .onAppear { model.load() }
        }
    }
}

#Preview {
    ChatScreen()
}

#Preview("Dark") {
    ChatScreen().preferredColorScheme(.dark)
}
