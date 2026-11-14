
import ActivityKit
import AppIntents
import Foundation
import SwiftUI

// Widget previews. The preprocessor rewrites
//     #Preview("name", as: .systemSmall) { MyWidget() } timeline: { ... }
//     #Preview("name", as: .dynamicIsland(.compact), using: attributes) { MyLiveActivity() } contentStates: { ... }
// to `WidgetKit._WidgetPreview(...)` with the same arguments, and a file with a widget or a
// widget bundle but no preview to `_WidgetPreview(widget:)` / `_WidgetPreview(bundle:)`.
// Each expands to one image per timeline entry, content state, or supported family.

public struct ActivityPreviewViewKind: Hashable, Sendable {
    public enum DynamicIslandPresentation: Hashable, Sendable { case compact, expanded, minimal }
    let id: _ActivityPresentationID
    public static let content = ActivityPreviewViewKind(id: .lockScreen)
    public static func dynamicIsland(_ presentation: DynamicIslandPresentation) -> ActivityPreviewViewKind {
        switch presentation {
        case .compact: return ActivityPreviewViewKind(id: .compact)
        case .expanded: return ActivityPreviewViewKind(id: .expanded)
        case .minimal: return ActivityPreviewViewKind(id: .minimal)
        }
    }
    var label: String {
        switch id {
        case .lockScreen: return "content"
        case .compact: return "dynamicIsland compact"
        case .expanded: return "dynamicIsland expanded"
        case .minimal: return "dynamicIsland minimal"
        }
    }
}

/// Collects the entries of a preview's `timeline:` / `contentStates:` closure.
@resultBuilder
public enum _PreviewArrayBuilder {
    public static func buildExpression<T>(_ value: T) -> [T] { [value] }
    public static func buildExpression<T>(_ values: [T]) -> [T] { values }
    public static func buildBlock<T>(_ parts: [T]...) -> [T] { parts.flatMap { $0 } }
    public static func buildArray<T>(_ parts: [[T]]) -> [T] { parts.flatMap { $0 } }
    public static func buildOptional<T>(_ part: [T]?) -> [T] { part ?? [] }
    public static func buildEither<T>(first: [T]) -> [T] { first }
    public static func buildEither<T>(second: [T]) -> [T] { second }
    public static func buildLimitedAvailability<T>(_ part: [T]) -> [T] { part }
}

@MainActor
public struct _WidgetPreview: _PreviewEntryGroup {
    let expand: @MainActor () -> [_PreviewEntry]
    public var _previewEntries: [_PreviewEntry] { expand() }

    // MARK: Timeline widgets

    public init<W: Widget, E: TimelineEntry>(_ name: String? = nil, as family: WidgetFamily, widget: @escaping @MainActor () -> W,
                                             @_PreviewArrayBuilder timeline: @escaping @MainActor () -> [E]) {
        expand = {
            let entries = timeline()
            return Self.entries(name: name, widget: widget, family: family, count: entries.count) { entries[$0] }
        }
    }

    public init<W: Widget, P: TimelineProvider>(_ name: String? = nil, as family: WidgetFamily, widget: @escaping @MainActor () -> W,
                                                timelineProvider: @escaping @MainActor () -> P) {
        expand = {
            let family = Self.family(family)
            let entries = _ProviderRunner.timeline(timelineProvider(), .preview(family)) ?? []
            return Self.entries(name: name, widget: widget, family: family, count: entries.count) { entries[$0] }
        }
    }

    public init<W: Widget, P: AppIntentTimelineProvider>(_ name: String? = nil, as family: WidgetFamily, using intent: P.Intent,
                                                         widget: @escaping @MainActor () -> W,
                                                         timelineProvider: @escaping @MainActor () -> P) {
        expand = {
            let family = Self.family(family)
            let entries = _ProviderRunner.timeline(timelineProvider(), intent, .preview(family)) ?? []
            return Self.entries(name: name, widget: widget, family: family, count: entries.count) { entries[$0] }
        }
    }

    /// `--widget-family` overrides the family a preview asks for.
    static func family(_ requested: WidgetFamily) -> WidgetFamily {
        _WidgetHostOptions.current.family.map(WidgetFamily.init) ?? requested
    }

    static func entries<W: Widget>(name: String?, widget: @escaping @MainActor () -> W, family requested: WidgetFamily, count: Int,
                                   entry: @escaping @MainActor (Int) -> any TimelineEntry) -> [_PreviewEntry] {
        let family = Self.family(requested)
        let base = name ?? "\(W.self) \(family)"
        return (0..<count).map { index in
            let label = count > 1 ? "\(base) entry \(index + 1)" : base
            return _PreviewEntry(label, layout: "fit") {
                Self.canvas(widget(), family: family) { entry(index) }
            }
        }
    }

    /// The canvas for one entry. The entry and the description are made while the canvas
    /// resolves, so provider calls and warnings happen during the render.
    static func canvas<W: Widget>(_ widget: W, family: WidgetFamily, entry: @escaping @MainActor () -> any TimelineEntry) -> _WidgetCanvas {
        let description = widget._widgetDescription()
        return _WidgetCanvas(family: family._id, renderingMode: _WidgetHostOptions.current.renderingMode,
                             contentMarginsDisabled: description?.contentMarginsDisabled ?? false,
                             backgroundRemovable: description?.backgroundRemovable ?? true) {
            guard let description, let render = description.render else {
                return message("\(W.self) is not a timeline widget")
            }
            if let families = description.supportedFamilies, !families.contains(family) {
                _WidgetHost.warn("\(W.self) does not list \(family) in supportedFamilies")
            }
            let value = entry()
            _WidgetHost.setReferenceDate(value.date)
            return render(value) ?? message("The preview's entries are \(type(of: value)), but \(W.self) shows \(description.entryType.map { "\($0)" } ?? "another type")")
        }
    }

    static func message(_ text: String) -> AnyView {
        _WidgetHost.warn(text)
        return AnyView(Text(text).font(.caption).foregroundStyle(.red).padding(8))
    }

    // MARK: Live Activities

    public init<W: Widget, A: ActivityAttributes>(_ name: String? = nil, as kind: ActivityPreviewViewKind, using attributes: A,
                                                  widget: @escaping @MainActor () -> W,
                                                  @_PreviewArrayBuilder contentStates: @escaping @MainActor () -> [A.ContentState]) {
        expand = {
            let states = contentStates()
            let base = name ?? "\(W.self) \(kind.label)"
            return states.indices.map { index in
                let label = states.count > 1 ? "\(base) state \(index + 1)" : base
                return _PreviewEntry(label, layout: "fit") {
                    Self.activityCanvas(widget(), kind: kind, attributes: attributes, state: states[index])
                }
            }
        }
    }

    public init<W: Widget, A: ActivityAttributes>(_ name: String? = nil, as kind: ActivityPreviewViewKind, using attributes: A,
                                                  widget: @escaping @MainActor () -> W,
                                                  @_PreviewArrayBuilder contents: @escaping @MainActor () -> [ActivityContent<A.ContentState>]) {
        self.init(name, as: kind, using: attributes, widget: widget, contentStates: { contents().map(\.state) })
    }

    static func activityCanvas<W: Widget, A: ActivityAttributes>(_ widget: W, kind: ActivityPreviewViewKind, attributes: A,
                                                                 state: A.ContentState) -> AnyView {
        guard let activity = widget._widgetDescription()?.activity else {
            return AnyView(_WidgetCanvasMessage(text: "\(W.self) has no ActivityConfiguration"))
        }
        guard let (lockScreen, island) = activity.make(attributes, state) else {
            return AnyView(_WidgetCanvasMessage(text: "\(W.self) shows \(activity.attributesType), but the preview uses \(A.self)"))
        }
        return AnyView(_LiveActivityCanvas(presentation: kind.id, lockScreen: { lockScreen }, backgroundTint: nil,
                                           expanded: { island.expanded }, compactLeading: { island.compactLeading },
                                           compactTrailing: { island.compactTrailing }, minimal: { island.minimal },
                                           keylineTint: island.keyline, margins: island.margins))
    }

    // MARK: Widgets without a preview

    public init<W: Widget>(widget: W) {
        expand = { Self.placeholderEntries([widget], prefix: nil) }
    }

    public init<B: WidgetBundle>(bundle: B) {
        expand = { Self.placeholderEntries(bundle.body._widgets, prefix: nil) }
    }

    /// One image per supported family (or the `--widget-family` one), from the provider's snapshot.
    static func placeholderEntries(_ widgets: [any Widget], prefix: String?) -> [_PreviewEntry] {
        var result: [_PreviewEntry] = []
        var skipped: [String] = []
        for widget in widgets {
            result += placeholderEntries(widget, skipped: &skipped)
        }
        if result.isEmpty {
            let text = skipped.isEmpty ? "No widget to render" : skipped.joined(separator: "\n")
            result.append(_PreviewEntry("widgets", layout: "fit") { _WidgetCanvasMessage(text: text) })
        }
        return result
    }

    static func placeholderEntries<W: Widget>(_ widget: W, skipped: inout [String]) -> [_PreviewEntry] {
        guard let description = widget._widgetDescription() else {
            skipped.append("\(W.self) has no widget configuration")
            return []
        }
        if description.activity != nil {
            skipped.append("\(W.self) is a Live Activity: add #Preview(\"…\", as: .content, using: …) { \(W.self)() } contentStates: { … } to render it")
            return []
        }
        guard let previewEntry = description.previewEntry else { return [] }
        let defaults: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        var families = (description.supportedFamilies ?? defaults).filter { _WidgetHost.supports($0._id) }
        if let wanted = _WidgetHostOptions.current.family.map(WidgetFamily.init) {
            families = families.contains(wanted) ? [wanted] : []
            if families.isEmpty { skipped.append("\(W.self) does not support \(wanted)") }
        }
        return families.map { family in
            _PreviewEntry("\(W.self) \(family)", layout: "fit") {
                Self.canvas(widget, family: family) { previewEntry(.preview(family)) }
            }
        }
    }
}

/// A plain message in place of a preview that cannot be rendered (also reported as a warning).
struct _WidgetCanvasMessage: View {
    let text: String
    var body: some View {
        _WidgetPreview.message(text)
    }
}
