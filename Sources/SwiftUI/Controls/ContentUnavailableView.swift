// The standard empty-state view: large secondary symbol, title, description, optional actions.

public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    let label: Label
    let description: Description
    let actions: Actions

    public init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
                @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                label
                    .labelStyle(_UnavailableLabelStyle())
                description
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            actions
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct _UnavailableLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            configuration.title
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
        }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    public init(_ title: LocalizedStringKey, image name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, image: name) }, description: { description })
    }
    public init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description })
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description })
    }
}

public struct SearchUnavailableContent {
    public struct Label: View {
        let query: String?
        public var body: some View {
            SwiftUI.Label(query.map { "No Results for \u{201C}\($0)\u{201D}" } ?? "No Results", systemImage: "magnifyingglass")
        }
    }
    public struct Description: View {
        public var body: some View { Text("Check the spelling or try a new search.") }
    }
    public struct Actions: View {
        public var body: some View { EmptyView() }
    }
}

extension ContentUnavailableView where Label == SearchUnavailableContent.Label, Description == SearchUnavailableContent.Description,
                                       Actions == SearchUnavailableContent.Actions {
    public static var search: ContentUnavailableView<Label, Description, Actions> {
        ContentUnavailableView(label: { SearchUnavailableContent.Label(query: nil) }, description: { SearchUnavailableContent.Description() },
                               actions: { SearchUnavailableContent.Actions() })
    }
    public static func search(text: String) -> ContentUnavailableView<Label, Description, Actions> {
        ContentUnavailableView(label: { SearchUnavailableContent.Label(query: text) }, description: { SearchUnavailableContent.Description() },
                               actions: { SearchUnavailableContent.Actions() })
    }
}
