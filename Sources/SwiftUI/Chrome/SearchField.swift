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
    var placement: SearchFieldPlacement.Kind = .automatic
    var toolbarBehavior: SearchToolbarBehavior = .automatic
}

public struct SearchFieldPlacement: Sendable {
    enum Kind: Sendable { case automatic, toolbar, toolbarPrincipal, sidebar, navigationBarDrawer }
    let kind: Kind
    public struct NavigationBarDrawerDisplayMode: Sendable {
        public static let automatic = NavigationBarDrawerDisplayMode()
        public static let always = NavigationBarDrawerDisplayMode()
    }
    public static let automatic = SearchFieldPlacement(kind: .automatic)
    public static let toolbar = SearchFieldPlacement(kind: .toolbar)
    public static let toolbarPrincipal = SearchFieldPlacement(kind: .toolbarPrincipal)
    public static let sidebar = SearchFieldPlacement(kind: .sidebar)
    public static let navigationBarDrawer = SearchFieldPlacement(kind: .navigationBarDrawer)
    public static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement {
        SearchFieldPlacement(kind: .navigationBarDrawer)
    }
}

/// iOS 26: `.minimize` shows a toolbar search field as a button until it is tapped.
public struct SearchToolbarBehavior: Hashable, Sendable {
    let raw: Int
    public static let automatic = SearchToolbarBehavior(raw: 0)
    public static let minimize = SearchToolbarBehavior(raw: 1)
}

enum SearchToolbarBehaviorKey: EnvironmentKey { static let defaultValue = SearchToolbarBehavior.automatic }
extension EnvironmentValues {
    var searchToolbarBehavior: SearchToolbarBehavior {
        get { self[SearchToolbarBehaviorKey.self] }
        set { self[SearchToolbarBehaviorKey.self] = newValue }
    }
}

/// How a Liquid Glass bar draws the field (nil: the iOS 18 rounded rectangle).
enum GlassSearchStyle {
    /// Floating glass capsule at the bottom of the screen.
    case bottom
    /// Under the title, a capsule with the neutral fill.
    case drawer
    /// `searchToolbarBehavior(.minimize)`: a glass circle with the magnifying glass.
    case minimized
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
    let configuration: SearchConfiguration
    var label: Node { children[0] }
    /// Liquid Glass look, chosen by the navigation stack during layout.
    var glassStyle: GlassSearchStyle?
    private var glassAppearance: GlassAppearance?
    /// The minimized field is a bar button: its glyph uses the label color.
    private let buttonGlyph: _Paint
    /// Microphone glyph of the glass field (dictation).
    private var microphone: Node? { children.count > 1 ? children[1] : nil }

    init(configuration: SearchConfiguration, env: EnvironmentValues) {
        let scheme = env.colorScheme
        self.configuration = configuration
        fill = .color(SystemColor.tertiaryFill.resolve(scheme))
        glass = .color(SystemColor.secondaryLabel.resolve(scheme))
        buttonGlyph = .color(SystemColor.label.resolve(scheme))
        var textEnv = env
        textEnv.font = .body
        textEnv.lineLimit = 1
        textEnv.fontWeight = nil
        let showsText = !configuration.text.isEmpty
        showsPrompt = !showsText
        textEnv.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(.color((showsText ? SystemColor.label : SystemColor.secondaryLabel).resolve(scheme))))
        textEnv.foregroundStyleLevels = nil
        let text = showsText ? Text(verbatim: configuration.text) : (configuration.prompt ?? Text(verbatim: "Search"))
        var nodes: [Node] = [text.makeNode(textEnv)]
        if env.designLanguage.isGlass {
            var micEnv = env
            micEnv.font = .system(size: 17)
            micEnv.imageScale = .medium
            micEnv.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(glass))
            micEnv.foregroundStyleLevels = nil
            let mic = ImageNode(content: Image(systemName: "mic.fill").content(in: micEnv), isResizable: false)
            mic.isDecorative = true
            nodes.append(mic)
            glassAppearance = GlassAppearance.system(.regular, scheme: scheme, design: env.designLanguage)
        }
        super.init(children: nodes)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        if let style = glassStyle {
            let g = NavigationGlassMetrics.search
            switch style {
            case .minimized: return CGSize(width: g.bottomHeight, height: g.bottomHeight)
            case .bottom: return CGSize(width: proposal.width ?? 200, height: g.bottomHeight)
            case .drawer: return CGSize(width: proposal.width ?? 200, height: g.drawerHeight)
            }
        }
        return CGSize(width: proposal.width ?? 200, height: SearchFieldMetrics.height)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        if let style = glassStyle {
            layoutGlass(style, size: size, ctx)
            return
        }
        let m = SearchFieldMetrics.self
        let width = max(0, size.width - m.textLeading - m.textTrailing)
        let s = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        label.place(at: CGPoint(x: m.textLeading, y: (size.height - s.height) / 2), size: CGSize(width: min(width, s.width), height: s.height), ctx)
    }
    override func drawContent(_ p: Painter) {
        if let style = glassStyle {
            drawGlass(style, p)
            return
        }
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

    // MARK: Liquid Glass

    private func layoutGlass(_ style: GlassSearchStyle, size: CGSize, _ ctx: PlaceContext) {
        let g = NavigationGlassMetrics.search
        if style == .minimized {
            label.place(at: .zero, size: .zero, ctx)
            microphone?.place(at: .zero, size: .zero, ctx)
            return
        }
        var trailing = g.textTrailing
        if let microphone {
            let s = microphone.sizeThatFits(.unspecified)
            microphone.place(at: CGPoint(x: size.width - g.micTrailing - s.width, y: (size.height - s.height) / 2), size: s, ctx)
            trailing = g.micTrailing + s.width + 8
        }
        let width = max(0, size.width - g.textLeading - trailing)
        let s = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        label.place(at: CGPoint(x: g.textLeading, y: (size.height - s.height) / 2),
                    size: CGSize(width: min(width, s.width), height: s.height), ctx)
    }

    private func drawGlass(_ style: GlassSearchStyle, _ p: Painter) {
        let g = NavigationGlassMetrics.search
        let bounds = CGRect(origin: .zero, size: frame.size)
        let outline = GlassOutline.roundedRect(bounds, radius: bounds.height / 2)
        if style == .drawer {
            p.fill(outline.path, with: fill, in: bounds)
        } else if let glassAppearance {
            p.fillGlass(outline, appearance: glassAppearance)
        }
        // Magnifying glass: a ring with a short handle towards the bottom right.
        let r = g.glyphRadius
        let c = CGPoint(x: style == .minimized ? bounds.midX - 1.2 : g.glyphCenterX, y: bounds.midY - 1.2)
        let paint = style == .minimized ? buttonGlyph : glass
        p.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: paint,
                 style: StrokeStyle(lineWidth: g.glyphLineWidth), in: bounds)
        let d = r / 2.squareRoot()
        var handle = Path()
        handle.move(to: CGPoint(x: c.x + d + 0.6, y: c.y + d + 0.6))
        handle.addLine(to: CGPoint(x: c.x + d + r * 0.75, y: c.y + d + r * 0.75))
        p.stroke(handle, with: paint, style: StrokeStyle(lineWidth: g.glyphLineWidth + 0.4, lineCap: .round), in: bounds)
        if style != .minimized { drawChildren(p) }
    }
}

extension View {
    func setSearch(_ text: Binding<String>, _ prompt: Text?, _ placement: SearchFieldPlacement = .automatic) -> some View {
        let base = SearchConfiguration(text: text.wrappedValue, prompt: prompt, placement: placement.kind)
        return navigationChrome { chrome, ctx in
            var configuration = base
            configuration.toolbarBehavior = ctx.env.searchToolbarBehavior
            chrome.search = configuration
        }
        .env { $0.navigationSearch = base }
    }

    /// iOS 26: `.minimize` collapses a toolbar search field into a button.
    public func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View {
        env { $0.searchToolbarBehavior = behavior }
    }

    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
        setSearch(text, prompt, placement)
    }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
        setSearch(text, Text(prompt), placement)
    }
    @_disfavoredOverload
    public func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
        setSearch(text, Text(prompt), placement)
    }
    public func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                           prompt: Text? = nil) -> some View {
        setSearch(text, prompt, placement)
    }
    public func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                           prompt: LocalizedStringKey) -> some View {
        setSearch(text, Text(prompt), placement)
    }
    @_disfavoredOverload
    public func searchable<S: StringProtocol>(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                                              prompt: S) -> some View {
        setSearch(text, Text(prompt), placement)
    }
    @available(*, deprecated, message: "Use searchSuggestions(_:)")
    public func searchable<S: View>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
                                    @ViewBuilder suggestions: () -> S) -> some View {
        setSearch(text, prompt, placement)
    }

    public func searchSuggestions<S: View>(@ViewBuilder _ suggestions: () -> S) -> some View { self }
    public func searchSuggestions(_ visibility: Visibility, for placements: SearchSuggestionsPlacement.Set) -> some View { self }
    public func searchCompletion(_ completion: String) -> some View { self }
    public func searchScopes<V: Hashable, S: View>(_ scope: Binding<V>, @ViewBuilder scopes: () -> S) -> some View { self }
    public func searchScopes<V: Hashable, S: View>(_ scope: Binding<V>, activation: SearchScopeActivation, @ViewBuilder _ scopes: () -> S) -> some View { self }
    public func searchPresentationToolbarBehavior(_ behavior: SearchPresentationToolbarBehavior) -> some View { self }
}
