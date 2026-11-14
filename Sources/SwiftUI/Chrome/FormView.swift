// Form: on iPhone, an inset-grouped List whose rows host controls.

public struct Form<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { List<Never, Content>(content: content, forcedStyle: .insetGrouped) }
}
