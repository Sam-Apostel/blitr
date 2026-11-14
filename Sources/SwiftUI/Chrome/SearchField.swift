// `.searchable`: the search field a NavigationStack shows under its title.

enum SearchFieldMetrics {
    /// Whole region added under the title: gap + field + gap.
    static let regionHeight: CGFloat = 52
    static let topGap: CGFloat = 8
    static let height: CGFloat = 36
    static let cornerRadius: CGFloat = 10
    /// Magnifying glass: lens centre from the field's leading edge, lens radius, stroke width.
    static let glassCenterX: CGFloat = 16
    static let glassRadius: CGFloat = 6.2
    static let glassLineWidth: CGFloat = 1.9
    static let glassHandleLength: CGFloat = 4.6
    static let textLeading: CGFloat = 30
    static let textTrailing: CGFloat = 8
}

struct SearchConfiguration {
    var text: String
    var prompt: Text?
}

public struct SearchFieldPlacement: Sendable {
    public struct NavigationBarDrawerDisplayMode: Sendable {
        public static let automatic = NavigationBarDrawerDisplayMode()
        public static let always = NavigationBarDrawerDisplayMode()
    }
    public static let automatic = SearchFieldPlacement()
    public static let toolbar = SearchFieldPlacement()
    public static let toolbarPrincipal = SearchFieldPlacement()
    public static let sidebar = SearchFieldPlacement()
    public static let navigationBarDrawer = SearchFieldPlacement()
    public static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement { SearchFieldPlacement() }
}

public struct SearchPresentationToolbarBehavior: Sendable {
    public static let automatic = SearchPresentationToolbarBehavior()
    public static let avoidHidingContent = SearchPresentationToolbarBehavior()
}
public struct SearchScopeActivation: Sendable {
    public static let automatic = SearchScopeActivation()
    public static let onTextEntry = SearchScopeActivation()
    public static let onSearchPresentation = SearchScopeActivation()
}
public struct SearchSuggestionsPlacement: Sendable {
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let menu = Set(rawValue: 1)
        public static let content = Set(rawValue: 2)
    }
    public static let automatic = SearchSuggestionsPlacement()
    public static let menu = SearchSuggestionsPlacement()
    public static let content = SearchSuggestionsPlacement()
}

final class SearchFieldNode: Node {
    let fill: _Paint
    let glass: _Paint
    /// True while the field shows its prompt rather than typed text (accessibility value vs label).
    let showsPrompt: Bool
    var label: Node { children[0] }

    init(configuration: SearchConfiguration, env: EnvironmentValues) {
        let scheme = env.colorScheme
        fill = .color(SystemColor.tertiaryFill.resolve(scheme))
        glass = .color(SystemColor.secondaryLabel.resolve(scheme))
        var textEnv = env
        textEnv.font = .body
        textEnv.lineLimit = 1
        textEnv.fontWeight = nil
        let showsText = !configuration.text.isEmpty
        showsPrompt = !showsText
        textEnv.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(.color((showsText ? SystemColor.label : SystemColor.secondaryLabel).resolve(scheme))))
        textEnv.foregroundStyleLevels = nil
        let text = showsText ? Text(verbatim: configuration.text) : (configuration.prompt ?? Text(verbatim: "Search"))
        super.init(children: [text.makeNode(textEnv)])
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? 200, height: SearchFieldMetrics.height)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let m = SearchFieldMetrics.self
        let width = max(0, size.width - m.textLeading - m.textTrailing)
        let s = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        label.place(at: CGPoint(x: m.textLeading, y: (size.height - s.height) / 2), size: CGSize(width: min(width, s.width), height: s.height), ctx)
    }
    override func drawContent(_ p: Painter) {
        let m = SearchFieldMetrics.self
        let bounds = CGRect(origin: .zero, size: frame.size)
        p.fill(Path(roundedRect: bounds, cornerRadius: m.cornerRadius, style: .continuous), with: fill, in: bounds)
        // Magnifying glass: a ring with a short handle towards the bottom right.
        let c = CGPoint(x: m.glassCenterX - 1, y: frame.height / 2 - 1)
        var lens = Path()
        lens.addEllipse(in: CGRect(x: c.x - m.glassRadius, y: c.y - m.glassRadius, width: m.glassRadius * 2, height: m.glassRadius * 2))
        p.stroke(lens, with: glass, style: StrokeStyle(lineWidth: m.glassLineWidth), in: bounds)
        let d = m.glassRadius / 2.squareRoot()
        var handle = Path()
        handle.move(to: CGPoint(x: c.x + d + 0.6, y: c.y + d + 0.6))
        handle.addLine(to: CGPoint(x: c.x + d + m.glassHandleLength, y: c.y + d + m.glassHandleLength))
        p.stroke(handle, with: glass, style: StrokeStyle(lineWidth: m.glassLineWidth + 0.4, lineCap: .round), in: bounds)
        drawChildren(p)
    }
}

extension View {
    func setSearch(_ text: Binding<String>, _ prompt: Text?) -> some View {
        let configuration = SearchConfiguration(text: text.wrappedValue, prompt: prompt)
        return navigationChrome { chrome, _ in chrome.search = configuration }
            .env { $0.navigationSearch = configuration }
    }

    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
        setSearch(text, prompt)
    }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
        setSearch(text, Text(prompt))
    }
    @_disfavoredOverload
    public func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
        setSearch(text, Text(prompt))
    }
    public func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                           prompt: Text? = nil) -> some View {
        setSearch(text, prompt)
    }
    public func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                           prompt: LocalizedStringKey) -> some View {
        setSearch(text, Text(prompt))
    }
    @_disfavoredOverload
    public func searchable<S: StringProtocol>(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                                              prompt: S) -> some View {
        setSearch(text, Text(prompt))
    }
    @available(*, deprecated, message: "Use searchSuggestions(_:)")
    public func searchable<S: View>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
                                    @ViewBuilder suggestions: () -> S) -> some View {
        setSearch(text, prompt)
    }

    public func searchSuggestions<S: View>(@ViewBuilder _ suggestions: () -> S) -> some View { self }
    public func searchSuggestions(_ visibility: Visibility, for placements: SearchSuggestionsPlacement.Set) -> some View { self }
    public func searchCompletion(_ completion: String) -> some View { self }
    public func searchScopes<V: Hashable, S: View>(_ scope: Binding<V>, @ViewBuilder scopes: () -> S) -> some View { self }
    public func searchScopes<V: Hashable, S: View>(_ scope: Binding<V>, activation: SearchScopeActivation, @ViewBuilder _ scopes: () -> S) -> some View { self }
    public func searchPresentationToolbarBehavior(_ behavior: SearchPresentationToolbarBehavior) -> some View { self }
}
