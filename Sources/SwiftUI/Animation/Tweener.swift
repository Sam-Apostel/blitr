// Interpolates between two laid-out node trees of the same view: the frames SwiftUI would draw while
// an animation runs.
//
//  - Nodes are matched by structural identity (`CaptureInfo.path`, stamped at resolve time) plus their
//    class and occurrence; unstamped container nodes take the identity of their first stamped descendant.
//  - Matched nodes interpolate their frame (relative to the parent, so moving containers carry their
//    children), effect parameters (opacity, scale, rotation, blur, shadow), offsets, shape geometry
//    (`animatableData`: corner radii, trim) and paints (colors, gradients with the same stops). Text and
//    images whose content changed cross-fade (as SwiftUI's default `.opacity` content transition does).
//  - Unmatched nodes are insertions and removals: they appear and disappear through their `.transition`
//    (opacity by default), drawn in their place among their siblings.
//  - `matchedGeometryEffect` pairs a removed and an inserted view with the same id: the inserted one moves
//    from the removed one's frame, the two cross-fade.
//  - Each node animates with the animation in effect for it: the step's transaction (`withAnimation`),
//    overridden by `.animation(_:value:)` when the value changed, `.transaction` modifiers, and the system
//    animations of presentations and navigation (SystemTransitions.swift).
//
// The tweener hooks into `Node.draw` while `Tweener.active` is set: the renderer draws the new tree as
// usual and each node is drawn as it looks at `time`.

struct NodeKey: Hashable {
    var base: AnyHashable
    var occurrence: Int
}

@MainActor
final class Tweener {
    static var active: Tweener?
    /// The color behind everything (a pushed screen is opaque with it while it slides in).
    static var canvasBackground = RGBA.white

    let before: Node
    let after: Node
    let transaction: Transaction
    /// Seconds since the change.
    var time: Double = 0
    /// A fixed fraction for every animated node (PhaseAnimator segments) instead of evaluating curves at `time`.
    var fixedProgress: Double?

    private var keys: [ObjectIdentifier: NodeKey] = [:]
    private var match: [ObjectIdentifier: Node] = [:]
    private var reverse: [ObjectIdentifier: Node] = [:]
    private var reparented: Set<ObjectIdentifier> = []
    private var parentAfter: [ObjectIdentifier: Node] = [:]
    private var parentBefore: [ObjectIdentifier: Node] = [:]
    private var indexInParent: [ObjectIdentifier: Int] = [:]
    private var inAfter: Set<ObjectIdentifier> = []
    private var afterHasMatch: Set<ObjectIdentifier> = []
    private var beforeHasMatch: Set<ObjectIdentifier> = []
    /// The animation each after node (and each removed before root) changes with; nil snaps.
    private var animations: [ObjectIdentifier: Animation?] = [:]
    /// Navigation pushes/pops: the stacks whose screen changed, with the direction.
    private var navigationChanges: [ObjectIdentifier: Bool] = [:]
    private var heroes: [ObjectIdentifier: Node] = [:]
    private var heroSources: Set<ObjectIdentifier> = []
    private var drawnRemoved: Set<ObjectIdentifier> = []
    private var plainDepth = 0
    private var composing = false
    private var inRootPass = false
    private var heroList: [(Node, Node)] = []
    private var retained: [Node] = []

    /// Longest animation of anything that changed.
    private(set) var duration: Double = 0
    /// Anything differs between the two trees (animated or not).
    private(set) var hasChanges = false
    /// False when an animation ends away from the new state (one cycle of an autoreversing repeatForever).
    private(set) var endsAtTarget = true
    private(set) var animationsUsed: [Animation] = []
    private(set) var notes: [String] = []

    init(before: Node, after: Node, transaction: Transaction) {
        self.before = before
        self.after = after
        self.transaction = transaction
        assignKeys(before, parent: nil, isAfter: false)
        assignKeys(after, parent: nil, isAfter: true)
        matchNodes()
        _ = markMatched(before, isAfter: false)
        _ = markMatched(after, isAfter: true)
        findHeroes()
        prepareAnimations(after, inherited: transaction.disablesAnimations ? nil : transaction.animation)
        measureChanges()
    }

    // MARK: Keys and matching

    private var occurrence: [AnyHashable: Int] = [:]

    private func baseKey(_ node: Node) -> AnyHashable {
        let cls = ObjectIdentifier(type(of: node))
        if let path = node.capture?.path { return AnyHashable([AnyHashable(path), AnyHashable(cls)]) }
        if let stamped = firstStamped(node) { return AnyHashable([AnyHashable(stamped), AnyHashable("^"), AnyHashable(cls)]) }
        return AnyHashable([AnyHashable("unstamped"), AnyHashable(cls)])
    }

    private func firstStamped(_ node: Node) -> IdentityPath? {
        for child in node.children {
            if let p = child.capture?.path { return p }
            if let p = firstStamped(child) { return p }
        }
        return nil
    }

    private func assignKeys(_ root: Node, parent: Node?, isAfter: Bool) {
        occurrence = [:]
        func visit(_ node: Node, _ parent: Node?, _ index: Int, _ parentKey: AnyHashable?) {
            let id = ObjectIdentifier(node)
            var base = baseKey(node)
            if node.capture?.path == nil, firstStamped(node) == nil, let parentKey {
                base = AnyHashable([parentKey, AnyHashable(index), base])
            }
            let n = occurrence[base, default: 0]
            occurrence[base] = n + 1
            let key = NodeKey(base: base, occurrence: n)
            keys[id] = key
            indexInParent[id] = index
            if isAfter {
                inAfter.insert(id)
                if let parent { parentAfter[id] = parent }
            } else if let parent {
                parentBefore[id] = parent
            }
            for (i, child) in node.children.enumerated() { visit(child, node, i, AnyHashable(key)) }
        }
        visit(root, parent, 0, nil)
        retained.append(root)
    }

    private func matchNodes() {
        var beforeByKey: [NodeKey: Node] = [:]
        func collect(_ node: Node) {
            if let k = keys[ObjectIdentifier(node)] { beforeByKey[k] = node }
            for c in node.children { collect(c) }
        }
        collect(before)
        func visit(_ node: Node) {
            let id = ObjectIdentifier(node)
            if let k = keys[id], let b = beforeByKey[k], type(of: b) == type(of: node) {
                match[id] = b
                reverse[ObjectIdentifier(b)] = node
            }
            for c in node.children { visit(c) }
        }
        visit(after)
        // The roots always correspond (a presentation host may wrap one of them).
        let afterBase = (after as? PresentationHostNode)?.base ?? after
        let beforeBase = (before as? PresentationHostNode)?.base ?? before
        if match[ObjectIdentifier(afterBase)] == nil, type(of: afterBase) == type(of: beforeBase) {
            match[ObjectIdentifier(afterBase)] = beforeBase
            reverse[ObjectIdentifier(beforeBase)] = afterBase
        }
        // A matched node whose parent is matched to a different node moved to another container.
        for (id, b) in match {
            guard let pa = parentAfter[id], let pb = parentBefore[ObjectIdentifier(b)] else { continue }
            if match[ObjectIdentifier(pa)] !== pb { reparented.insert(id) }
        }
    }

    @discardableResult
    private func markMatched(_ node: Node, isAfter: Bool) -> Bool {
        let id = ObjectIdentifier(node)
        var any = isAfter ? match[id] != nil : reverse[id] != nil
        for c in node.children where markMatched(c, isAfter: isAfter) { any = true }
        if any { if isAfter { afterHasMatch.insert(id) } else { beforeHasMatch.insert(id) } }
        return any
    }

    private func findHeroes() {
        var removed: [AnyHashable: Node] = [:]
        func collectBefore(_ node: Node) {
            let id = ObjectIdentifier(node)
            if reverse[id] == nil, let m = node.capture?.matched.first { removed[m.key] = node }
            for c in node.children { collectBefore(c) }
        }
        collectBefore(before)
        guard !removed.isEmpty else { return }
        func visitAfter(_ node: Node) {
            let id = ObjectIdentifier(node)
            if match[id] == nil, let m = node.capture?.matched.first, let source = removed[m.key] {
                heroes[id] = source
                heroList.append((node, source))
                heroSources.insert(ObjectIdentifier(source))
                removed[m.key] = nil
                return
            }
            for c in node.children { visitAfter(c) }
        }
        visitAfter(after)
    }

    // MARK: Animations

    private func prepareAnimations(_ node: Node, inherited: Animation?) {
        let id = ObjectIdentifier(node)
        var animation = inherited
        let beforeNode = match[id]
        if let scopes = node.capture?.scopes, !scopes.isEmpty {
            let beforeScopes = beforeNode?.capture?.scopes ?? []
            // Outer modifiers were appended last; they apply first.
            for (i, scope) in scopes.enumerated().reversed() {
                let old = i < beforeScopes.count ? beforeScopes[i].value : nil
                let changed: Bool
                if scope.value.value == nil { changed = true }
                else if let old { changed = !scope.value.equals(old.value) }
                else { changed = false }
                guard changed else { continue }
                switch scope {
                case .implicit(let a, _):
                    if !transaction.disablesAnimations { animation = a }
                case .transaction(let transform, _):
                    var t = transaction
                    t.animation = animation
                    transform(&t)
                    animation = t.disablesAnimations && t.animation == nil ? nil : t.animation
                }
            }
        }
        // Navigation: a new top screen pushes or pops with the system animation, bars included.
        if let nav = node as? NavigationStackNode, let old = beforeNode as? NavigationStackNode,
           keys[ObjectIdentifier(nav.content)] != keys[ObjectIdentifier(old.content)] {
            navigationChanges[id] = Tweener.navigationDepth(nav.content) < Tweener.navigationDepth(old.content)
            if !transaction.disablesAnimations { animation = SystemTransitions.navigation }
        }
        if let tabs = node as? TabViewNode, let old = beforeNode as? TabViewNode, tabs.selectedIndex != old.selectedIndex {
            animation = SystemTransitions.tabSwitch
        }
        animations[id] = .some(animation)
        for c in node.children { prepareAnimations(c, inherited: animation) }
    }

    /// 0 for a stack's root screen, n for the n-th pushed one (read from the content's identity).
    static func navigationDepth(_ content: Node) -> Int {
        guard let path = content.capture?.path else { return 0 }
        var depth = 0
        for c in path.components {
            guard let s = c.base as? String else { continue }
            for prefix in ["path", "pushed", "presented"] where s.hasPrefix(prefix) {
                if let n = Int(s.dropFirst(prefix.count)) { depth = max(depth, n + 1 + (prefix == "pushed" ? 100 : 0)) }
            }
        }
        return depth
    }

    private func animation(of node: Node) -> Animation? {
        animations[ObjectIdentifier(node)] ?? nil
    }

    /// The animation a removed before node goes away with: the one of the nearest ancestor still on screen.
    private func removalAnimation(of node: Node) -> Animation? {
        var n: Node? = parentBefore[ObjectIdentifier(node)]
        while let current = n {
            if let a = reverse[ObjectIdentifier(current)] { return animation(of: a) }
            n = parentBefore[ObjectIdentifier(current)]
        }
        return transaction.disablesAnimations ? nil : transaction.animation
    }

    private func use(_ a: Animation?) {
        guard let a else { return }
        duration = max(duration, a.duration)
        if !a.endsAtTarget { endsAtTarget = false }
        if !animationsUsed.contains(a) { animationsUsed.append(a) }
    }

    private func measureChanges() {
        func visit(_ node: Node) {
            let id = ObjectIdentifier(node)
            if let b = match[id] {
                if differs(node, b) {
                    hasChanges = true
                    use(animation(of: node))
                }
                for c in b.children where isRemovedRoot(c) {
                    hasChanges = true
                    use(transitionAnimation(c, insertion: false) ?? removalAnimation(of: c))
                }
            } else if !afterHasMatch.contains(id) {
                hasChanges = true
                use(transitionAnimation(node, insertion: true) ?? animation(of: node))
                if heroes[id] != nil { use(animation(of: node)) }
                return
            }
            for c in node.children { visit(c) }
        }
        visit(after)
        for change in presentationChanges() {
            hasChanges = true
            if !transaction.disablesAnimations { use(change.animation) }
        }
    }

    private func differs(_ a: Node, _ b: Node) -> Bool {
        if abs(a.frame.minX - b.frame.minX) > 0.01 || abs(a.frame.minY - b.frame.minY) > 0.01
            || abs(a.frame.width - b.frame.width) > 0.01 || abs(a.frame.height - b.frame.height) > 0.01 { return true }
        if let ea = a.capture?.effect, let eb = b.capture?.effect, ea.differs(from: eb) { return true }
        if let oa = a as? OffsetNode, let ob = b as? OffsetNode, oa.offset != ob.offset { return true }
        if let sa = a as? ShapeNode, let sb = b as? ShapeNode {
            if let da = sa.capture?.shape?.data, let db = sb.capture?.shape?.data, da != db { return true }
            if sa.layers.count != sb.layers.count { return true }
            for (la, lb) in zip(sa.layers, sb.layers) where la.paint.differs(from: lb.paint) { return true }
        }
        if let ta = a as? TextNode, let tb = b as? TextNode, Tweener.textDiffers(ta, tb) { return true }
        if let ia = a as? ImageNode, let ib = b as? ImageNode, Tweener.imageDiffers(ia, ib) { return true }
        return false
    }

    static func textDiffers(_ a: TextNode, _ b: TextNode) -> Bool {
        guard a.runs.count == b.runs.count else { return true }
        for (x, y) in zip(a.runs, b.runs) {
            if x.text != y.text || x.font != y.font || x.paint.differs(from: y.paint) { return true }
        }
        return false
    }

    static func imageDiffers(_ a: ImageNode, _ b: ImageNode) -> Bool {
        String(describing: a.imageSource) != String(describing: b.imageSource)
    }

    private func isRemovedRoot(_ node: Node) -> Bool {
        let id = ObjectIdentifier(node)
        return reverse[id] == nil && !beforeHasMatch.contains(id) && !heroSources.contains(id)
    }

    private func progress(_ a: Animation?) -> Double {
        guard let a else { return 1 }
        if let fixedProgress { return fixedProgress }
        return a.progress(at: time)
    }

    // MARK: Transitions

    private func transitionModel(_ node: Node) -> TransitionModel? {
        var n: Node? = node
        while let current = n {
            if let t = current.capture?.transition { return t }
            n = current.children.count == 1 ? current.children[0] : nil
        }
        return nil
    }

    /// An animation attached to the transition itself (`AnyTransition.animation(_:)`).
    private func transitionAnimation(_ node: Node, insertion: Bool) -> Animation? {
        guard let model = transitionModel(node), case .some(let a) = model.animation(insertion: insertion) else { return nil }
        return transaction.disablesAnimations ? nil : a
    }

    private var warnedCustom: Set<String> = []

    // MARK: Drawing

    func draw(_ node: Node, _ p: Painter) -> Bool {
        let id = ObjectIdentifier(node)
        // Matched-geometry pairs fly above everything else: they are drawn after the tree.
        if heroes[id] != nil { return true }
        if plainDepth > 0 { return heroSources.contains(id) }
        if node === after, !composing, !inRootPass {
            inRootPass = true
            drawnRemoved = []
            _ = draw(node, p)
            for (hero, source) in heroList { drawHero(hero, source, p) }
            inRootPass = false
            return true
        }
        if node === after, !composing, !presentationChanges().isEmpty {
            composing = true
            drawComposition(p)
            composing = false
            return true
        }
        guard inAfter.contains(id) else { return false }
        if let nav = parentAfter[id] as? NavigationStackNode, nav.content === node, let pop = navigationChanges[ObjectIdentifier(nav)], match[id] == nil {
            drawNavigationChange(nav, incoming: node, pop: pop, p)
            return true
        }
        if let parent = parentAfter[id] { drawRemovedSiblings(before: node, parent: parent, p) }
        if let b = match[id] {
            drawMatched(node, b, p)
        } else if afterHasMatch.contains(id) {
            p.save()
            p.translate(node.frame.minX, node.frame.minY)
            node.drawContent(p)
            p.restore()
        } else {
            drawInserted(node, p)
        }
        return true
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    private func drawMatched(_ a: Node, _ b: Node, _ p: Painter) {
        let id = ObjectIdentifier(a)
        let t = progress(animation(of: a))
        var f = CGRect(x: mix(b.frame.minX, a.frame.minX, t), y: mix(b.frame.minY, a.frame.minY, t),
                       width: mix(b.frame.width, a.frame.width, t), height: mix(b.frame.height, a.frame.height, t))
        if reparented.contains(id) {
            let parentOrigin = CGPoint(x: a.absoluteOrigin.x - a.frame.minX, y: a.absoluteOrigin.y - a.frame.minY)
            f.origin = CGPoint(x: mix(b.absoluteOrigin.x, a.absoluteOrigin.x, t) - parentOrigin.x,
                               y: mix(b.absoluteOrigin.y, a.absoluteOrigin.y, t) - parentOrigin.y)
        }
        // Text and images keep their final layout and move (SwiftUI does not reflow text mid-animation).
        if a is TextNode || a is ImageNode {
            f.size = a.frame.size
        }
        let saved = a.frame
        a.frame = f
        p.save()
        p.translate(f.minX, f.minY)
        drawContent(a, b, t, p)
        drawRemainingRemoved(of: b, p)
        p.restore()
        a.frame = saved
    }

    private func drawContent(_ a: Node, _ b: Node, _ t: Double, _ p: Painter) {
        let clamped = min(1, max(0, t))
        switch a {
        case let e as EffectNode:
            if let pa = e.capture?.effect, let pb = b.capture?.effect, pa.sameKind(pb) {
                var params = pb.interpolated(to: pa, t)
                if case .opacity(let o) = params { params = .opacity(min(1, max(0, o))) }
                if case .blur(let r) = params { params = .blur(max(0, r)) }
                params.draw(p, a.frame.size) { a.drawChildren(p) }
            } else {
                a.drawContent(p)
            }
        case let o as OffsetNode:
            let ob = (b as? OffsetNode)?.offset ?? o.offset
            p.save()
            p.translate(mix(ob.width, o.offset.width, t), mix(ob.height, o.offset.height, t))
            o.drawChildren(p)
            p.restore()
        case let s as ShapeNode:
            drawShape(s, b as? ShapeNode, t, p)
        case let text as TextNode:
            if let old = b as? TextNode, Tweener.textDiffers(text, old) {
                crossFade(old: old, new: text, clamped, p)
            } else {
                text.drawContent(p)
            }
        case let image as ImageNode:
            if let old = b as? ImageNode, Tweener.imageDiffers(image, old) {
                crossFade(old: old, new: image, clamped, p)
            } else {
                image.drawContent(p)
            }
        default:
            a.drawContent(p)
        }
    }

    private func crossFade(old: Node, new: Node, _ t: Double, _ p: Painter) {
        plainDepth += 1
        if t < 0.999 {
            p.saveLayer(.init(opacity: 1 - t))
            old.drawContent(p)
            p.restore()
        }
        if t > 0.001 {
            p.saveLayer(.init(opacity: t))
            new.drawContent(p)
            p.restore()
        }
        plainDepth -= 1
    }

    private func drawShape(_ a: ShapeNode, _ b: ShapeNode?, _ t: Double, _ p: Painter) {
        let bounds = CGRect(origin: .zero, size: a.frame.size)
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        var path = a.path
        if let b, let sa = a.capture?.shape, let sb = b.capture?.shape, sa.typeID == sb.typeID, sa.data.count == sb.data.count, sa.data != sb.data {
            let values = zip(sb.data, sa.data).map { $0 + ($1 - $0) * t }
            path = { sa.path(values, $0) }
        }
        let clamped = min(1, max(0, t))
        for (i, layer) in a.layers.enumerated() {
            var paint = layer.paint
            if let b, i < b.layers.count { paint = b.layers[i].paint.interpolated(to: layer.paint, clamped) }
            switch layer.op {
            case .fill(let style): p.fill(path(bounds), with: paint, in: bounds, style: style)
            case .stroke(let style): p.stroke(path(bounds), with: paint, style: style, in: bounds)
            case .strokeBorder(let style, let inset): p.stroke(inset(bounds), with: paint, style: style, in: bounds)
            }
        }
    }

    /// A navigation push or pop: the two screens slide as opaque pages, the lower one dimmed.
    private func drawNavigationChange(_ nav: NavigationStackNode, incoming: Node, pop: Bool, _ p: Painter) {
        let v = min(1, max(0, progress(animation(of: nav))))
        let hidden = CGFloat(1 - v)
        let width = nav.frame.width
        let outgoing = (match[ObjectIdentifier(nav)] as? NavigationStackNode)?.content
        func page(_ node: Node, offset: CGFloat, dim: Double) {
            p.save()
            p.translate(node.frame.minX + offset, node.frame.minY)
            let column = CGRect(x: -node.frame.minX, y: -node.frame.minY - 2000, width: width, height: nav.frame.height + 4000)
            p.fill(Path(column), with: .color(Tweener.canvasBackground), in: column)
            plainDepth += 1
            node.drawContent(p)
            plainDepth -= 1
            if dim > 0.001 { p.fill(Path(column), with: .color(RGBA(0, 0, 0, dim)), in: column) }
            p.restore()
        }
        if let outgoing { drawnRemoved.insert(ObjectIdentifier(outgoing)) }
        let parallax = width * SystemTransitions.navigationParallax
        if pop {
            // The screen underneath comes back from the left; the top one leaves to the right.
            page(incoming, offset: -parallax * hidden, dim: SystemTransitions.navigationDim * Double(hidden))
            if let outgoing, v < 0.9995 { page(outgoing, offset: width * CGFloat(v), dim: 0) }
        } else {
            if let outgoing, v < 0.9995 { page(outgoing, offset: -parallax * CGFloat(v), dim: SystemTransitions.navigationDim * v) }
            page(incoming, offset: width * hidden, dim: 0)
        }
    }

    private func drawInserted(_ node: Node, _ p: Painter) {
        let parent = parentAfter[ObjectIdentifier(node)]
        let a = transitionAnimation(node, insertion: true) ?? animation(of: node)
        let v = progress(a)
        let effect: TransitionEffect
        if parent is TabViewNode {
            effect = TransitionEffect()
        } else {
            let model = transitionModel(node) ?? .opacity
            warnCustom(model)
            effect = model.resolved(insertion: true).effect(visibility: v, size: node.frame.size)
        }
        p.save()
        p.translate(node.frame.minX, node.frame.minY)
        plainDepth += 1
        effect.apply(p, size: node.frame.size) { node.drawContent(p) }
        plainDepth -= 1
        p.restore()
    }

    private func drawRemoved(_ node: Node, _ p: Painter) {
        let id = ObjectIdentifier(node)
        guard !drawnRemoved.contains(id) else { return }
        drawnRemoved.insert(id)
        let a = transitionAnimation(node, insertion: false) ?? removalAnimation(of: node)
        guard a != nil else { return }
        let v = 1 - progress(a)
        guard v > 0.0005 else { return }
        let parent = parentBefore[id]
        let effect: TransitionEffect
        if parent is TabViewNode {
            return
        } else {
            let model = transitionModel(node) ?? .opacity
            warnCustom(model)
            effect = model.resolved(insertion: false).effect(visibility: v, size: node.frame.size)
        }
        p.save()
        p.translate(node.frame.minX, node.frame.minY)
        plainDepth += 1
        effect.apply(p, size: node.frame.size) { node.drawContent(p) }
        plainDepth -= 1
        p.restore()
    }

    private func warnCustom(_ model: TransitionModel) {
        guard let name = model.customName, warnedCustom.insert(name).inserted else { return }
        Runtime.current?.warn("transition \(name) is not interpolated by the capture; it fades instead")
    }

    private func drawRemovedSiblings(before node: Node, parent: Node, _ p: Painter) {
        guard let pb = match[ObjectIdentifier(parent)] else { return }
        let id = ObjectIdentifier(node)
        let limit: Int
        if let b = match[id], parentBefore[ObjectIdentifier(b)] === pb {
            limit = indexInParent[ObjectIdentifier(b)] ?? 0
        } else {
            limit = (indexInParent[id] ?? 0) + 1
        }
        for (i, c) in pb.children.enumerated() where i < limit && isRemovedRoot(c) { drawRemoved(c, p) }
    }

    private func drawRemainingRemoved(of b: Node, _ p: Painter) {
        for c in b.children where isRemovedRoot(c) { drawRemoved(c, p) }
    }

    // MARK: Matched geometry

    private func drawHero(_ node: Node, _ source: Node, _ p: Painter) {
        let t = progress(animation(of: node))
        let clamped = min(1, max(0, t))
        // Absolute positions, expressed in the space the root is drawn in.
        let base = CGPoint(x: after.absoluteOrigin.x - after.frame.minX, y: after.absoluteOrigin.y - after.frame.minY)
        let frame = CGRect(x: mix(source.absoluteOrigin.x, node.absoluteOrigin.x, t) - base.x,
                           y: mix(source.absoluteOrigin.y, node.absoluteOrigin.y, t) - base.y,
                           width: max(0.01, mix(source.frame.width, node.frame.width, t)),
                           height: max(0.01, mix(source.frame.height, node.frame.height, t)))
        func drawScaled(_ n: Node, opacity: Double) {
            guard opacity > 0.001, n.frame.width > 0, n.frame.height > 0 else { return }
            p.save()
            p.translate(frame.minX, frame.minY)
            p.scale(frame.width / n.frame.width, frame.height / n.frame.height)
            if opacity < 0.999 { p.saveLayer(.init(opacity: opacity)) }
            plainDepth += 1
            n.drawContent(p)
            plainDepth -= 1
            if opacity < 0.999 { p.restore() }
            p.restore()
        }
        // Shapes simply take the interpolated frame; other content scales with it and cross-fades.
        if let a = node as? ShapeNode, let b = source as? ShapeNode {
            let saved = a.frame
            a.frame = frame
            p.save()
            p.translate(frame.minX, frame.minY)
            drawShape(a, b, t, p)
            p.restore()
            a.frame = saved
            return
        }
        drawScaled(source, opacity: 1 - clamped)
        drawScaled(node, opacity: clamped)
    }

    // MARK: Presentations

    struct PresentationChange {
        var layer: PresentationLayerNode
        var insertion: Bool
        var animation: Animation
    }

    private var cachedPresentationChanges: [PresentationChange]?

    /// Layers presented or dismissed between the two trees (the root is the presentation host).
    private func presentationChanges() -> [PresentationChange] {
        if let cachedPresentationChanges { return cachedPresentationChanges }
        let beforeLayers = (before as? PresentationHostNode)?.layers ?? []
        let afterLayers = (after as? PresentationHostNode)?.layers ?? []
        var changes: [PresentationChange] = []
        for layer in afterLayers where match[ObjectIdentifier(layer)] == nil {
            changes.append(PresentationChange(layer: layer, insertion: true, animation: Tweener.systemAnimation(layer, insertion: true)))
        }
        for layer in beforeLayers where reverse[ObjectIdentifier(layer)] == nil {
            changes.append(PresentationChange(layer: layer, insertion: false, animation: Tweener.systemAnimation(layer, insertion: false)))
        }
        cachedPresentationChanges = changes
        return changes
    }

    static func systemAnimation(_ layer: PresentationLayerNode, insertion: Bool) -> Animation {
        switch layer {
        case is SheetLayerNode: return insertion ? SystemTransitions.sheet : SystemTransitions.sheetDismiss
        case is CoverLayerNode: return SystemTransitions.cover
        case let d as DimmedCardLayerNode:
            if d.atBottom { return SystemTransitions.dialog }
            return insertion ? SystemTransitions.alertPresent : SystemTransitions.alertDismiss
        default: return SystemTransitions.sheet
        }
    }

    private func drawComposition(_ p: Painter) {
        struct Entry { var layer: PresentationLayerNode; var visibility: Double; var change: Bool?; }
        let afterHost = after as? PresentationHostNode, beforeHost = before as? PresentationHostNode
        guard let hostFrame = (afterHost ?? beforeHost)?.frame else { return }
        var entries: [Entry] = []
        let changes = presentationChanges()
        func visibility(_ change: PresentationChange) -> Double {
            if transaction.disablesAnimations { return change.insertion ? 1 : 0 }
            let v = change.animation.progress(at: time)
            return change.insertion ? v : 1 - v
        }
        for layer in afterHost?.layers ?? [] {
            if let change = changes.first(where: { $0.insertion && $0.layer === layer }) {
                entries.append(Entry(layer: layer, visibility: visibility(change), change: true))
            } else {
                entries.append(Entry(layer: layer, visibility: 1, change: nil))
            }
        }
        for change in changes where !change.insertion {
            entries.append(Entry(layer: change.layer, visibility: visibility(change), change: false))
        }
        p.save()
        p.translate(hostFrame.minX, hostFrame.minY)
        func drawStack(_ i: Int) {
            guard i >= 0 else {
                if let afterHost {
                    afterHost.base.draw(p)
                } else {
                    // The new root is the presenter itself (the last presentation went away).
                    p.save()
                    p.translate(-hostFrame.minX, -hostFrame.minY)
                    after.draw(p)
                    p.restore()
                }
                return
            }
            let e = entries[i]
            let v = min(1, max(0, e.visibility))
            let rect = e.layer.frame
            switch e.layer.backdrop {
            case .none:
                if v < 1 { drawStack(i - 1) }
            case .dim(let amount):
                drawStack(i - 1)
                if amount > 0 { p.fill(Path(rect), with: .color(RGBA(0, 0, 0, amount * v)), in: rect) }
            case .pushBack(let presenterTop, let dim):
                p.fill(Path(rect), with: .color(RGBA(0, 0, 0, v)), in: rect)
                let s = 1 + (SheetMetrics.presenterScale - 1) * CGFloat(v)
                p.save()
                p.translate(rect.minX + rect.width * (1 - s) / 2, rect.minY + presenterTop * CGFloat(v))
                p.scale(s, s)
                p.translate(-rect.minX, -rect.minY)
                let clip = Path(roundedRect: rect, cornerRadius: SheetMetrics.presenterCornerRadius * CGFloat(v) / s, style: .continuous)
                p.clip(clip)
                drawStack(i - 1)
                p.fill(Path(rect), with: .color(RGBA(0, 0, 0, dim * v)), in: rect)
                p.restore()
            }
            guard let insertion = e.change else {
                e.layer.draw(p)
                return
            }
            guard e.visibility > 0.0005 else { return }
            let hidden = CGFloat(1 - e.visibility)
            p.save()
            var layered = false
            switch e.layer {
            case let sheet as SheetLayerNode:
                p.translate(0, (rect.height - sheet.cardRect.minY) * hidden)
            case is CoverLayerNode:
                p.translate(0, rect.height * hidden)
            case let d as DimmedCardLayerNode where d.atBottom:
                p.translate(0, (rect.height - d.card.frame.minY) * hidden)
            case let d as DimmedCardLayerNode:
                let c = CGPoint(x: rect.minX + d.card.frame.midX, y: rect.minY + d.card.frame.midY)
                let k = insertion ? 1 + (SystemTransitions.alertInitialScale - 1) * hidden : 1
                p.translate(c.x, c.y)
                p.scale(k, k)
                p.translate(-c.x, -c.y)
                p.saveLayer(.init(opacity: v))
                layered = true
            default:
                p.saveLayer(.init(opacity: v))
                layered = true
            }
            plainDepth += 1
            e.layer.draw(p)
            plainDepth -= 1
            if layered { p.restore() }
            p.restore()
        }
        drawStack(entries.count - 1)
        p.restore()
    }
}
