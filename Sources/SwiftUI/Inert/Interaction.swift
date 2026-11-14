// Pointer, drag and drop, context menus, swipe actions and pull-to-refresh: none of it is
// visible in a static frame, so these accept their arguments and return the view unchanged.

// MARK: - Hover

public struct HoverEffect: Sendable {
    enum Kind: Sendable { case automatic, highlight, lift }
    let kind: Kind
    public static let automatic = HoverEffect(kind: .automatic)
    public static let highlight = HoverEffect(kind: .highlight)
    public static let lift = HoverEffect(kind: .lift)
}

public enum HoverPhase: Equatable {
    case active(CGPoint)
    case ended
}

public struct HoverEffectGroup: Sendable {
    public init() {}
}

extension View {
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View { self }
    @_disfavoredOverload
    public func onContinuousHover(coordinateSpace: CoordinateSpace,
                                  perform action: @escaping (HoverPhase) -> Void) -> some View { self }
    public func onContinuousHover(coordinateSpace: some CoordinateSpaceProtocol = .local,
                                  perform action: @escaping (HoverPhase) -> Void) -> some View { self }
    /// No pointer on a static frame; on tvOS the effect is drawn while the enclosing focusable view has focus (Focus/TVFocusLook.swift).
    public func hoverEffect(_ effect: HoverEffect = .automatic, isEnabled: Bool = true) -> some View {
        modifier(HoverEffectModifier(effect: effect, isEnabled: isEnabled))
    }
    public func hoverEffectDisabled(_ disabled: Bool = true) -> some View { env { $0[HoverEffectDisabledKey.self] = disabled } }
}

// MARK: - Drag and drop

public enum DropOperation: Int, Sendable { case cancel, forbidden, copy, move }

public struct DropProposal: Sendable {
    public var operation: DropOperation
    public init(operation: DropOperation) { self.operation = operation }
}

public struct DropInfo {
    public var location: CGPoint
    public func hasItemsConforming(to contentTypes: [UTType]) -> Bool { false }
    public func hasItemsConforming(to contentTypes: [String]) -> Bool { false }
    public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] { [] }
}

@MainActor
public protocol DropDelegate {
    func validateDrop(info: DropInfo) -> Bool
    func dropEntered(info: DropInfo)
    func dropUpdated(info: DropInfo) -> DropProposal?
    func dropExited(info: DropInfo)
    func performDrop(info: DropInfo) -> Bool
}
extension DropDelegate {
    public func validateDrop(info: DropInfo) -> Bool { true }
    public func dropEntered(info: DropInfo) {}
    public func dropUpdated(info: DropInfo) -> DropProposal? { nil }
    public func dropExited(info: DropInfo) {}
}

extension View {
    public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View { self }
    public func onDrag<V: View>(_ data: @escaping () -> NSItemProvider, @ViewBuilder preview: () -> V) -> some View { self }

    public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                       perform action: @escaping (_ providers: [NSItemProvider]) -> Bool) -> some View { self }
    public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                       perform action: @escaping (_ providers: [NSItemProvider], _ location: CGPoint) -> Bool) -> some View { self }
    public func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View { self }

    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> some View { self }
    public func draggable<T: Transferable, V: View>(_ payload: @autoclosure @escaping () -> T,
                                                    @ViewBuilder preview: () -> V) -> some View { self }
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self,
                                                 action: @escaping (_ items: [T], _ location: CGPoint) -> Bool,
                                                 isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View { self }
}

// MARK: - Context menus, swipe actions, refresh

extension View {
    public func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View { self }
    public func contextMenu<MenuItems: View, Preview: View>(@ViewBuilder menuItems: () -> MenuItems,
                                                           @ViewBuilder preview: () -> Preview) -> some View { self }
    public func contextMenu<I: Hashable, M: View>(forSelectionType itemType: I.Type = I.self,
                                                  @ViewBuilder menu: @escaping (Set<I>) -> M,
                                                  primaryAction: ((Set<I>) -> Void)? = nil) -> some View { self }

    public func swipeActions<T: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
                                      @ViewBuilder content: () -> T) -> some View { self }

    public func refreshable(action: @escaping @Sendable () async -> Void) -> some View { self }
}
