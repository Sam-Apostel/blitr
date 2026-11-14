import SwiftUI
import UIKit

// Representables that are only plumbing: a UIKit container hosting SwiftUI (a zooming scroll view, a
// view pinned around a hosting controller's view), and invisible helpers (a view that reaches the window,
// one that installs a gesture recognizer). They draw the SwiftUI they host, or nothing. A view that draws
// itself (`draw(_:)`) or arranges UIKit subviews is still a placeholder naming the class.

/// SwiftUI content in a UIScrollView for pinch-zoom.
struct ZoomContainer<Content: View>: UIViewRepresentable {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.maximumZoomScale = 3
        let hosted = context.coordinator.host.view!
        hosted.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            hosted.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            hosted.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return scroll
    }
    func updateUIView(_ view: UIScrollView, context: Context) { context.coordinator.host.rootView = content }
    func makeCoordinator() -> Coordinator { Coordinator(host: UIHostingController(rootView: content)) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        init(host: UIHostingController<Content>) { self.host = host }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
    }
}

/// A view of the app's own class that wraps a hosting controller's view, with a card's corner radius.
struct CardHost: UIViewRepresentable {
    final class Container: UIView {}

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.layer.cornerRadius = 14
        container.clipsToBounds = true
        let host = UIHostingController(rootView: Label("Hosted in a UIView", systemImage: "square.stack")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.teal.opacity(0.25)))
        container.addSubview(host.view)
        return container
    }
    func updateUIView(_ view: Container, context: Context) {}
}

/// Reaches the window when it is added to one; draws nothing.
struct WindowProbe: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.tintAdjustmentMode = .normal
        }
    }
    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }
    func updateUIView(_ view: Probe, context: Context) {}
}

/// Installs a two-finger tap recognizer on an invisible view.
struct TwoFingerTap: UIViewRepresentable {
    let action: () -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fire))
        tap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

/// Draws itself with Core Graphics: cannot be shown, so it stays a placeholder.
struct Sparkline: UIViewRepresentable {
    final class LineView: UIView {
        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.move(to: CGPoint(x: 0, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.strokePath()
        }
    }
    func makeUIView(context: Context) -> LineView { LineView() }
    func updateUIView(_ view: LineView, context: Context) {}
}

#Preview("Containers") {
    VStack(spacing: 16) {
        ZoomContainer {
            RoundedRectangle(cornerRadius: 12).fill(Color.orange.gradient)
                .overlay(Text("Zoomable SwiftUI").font(.headline).foregroundStyle(.white))
        }
        .frame(height: 140)
        CardHost().frame(height: 80)
        Text("A probe and a gesture helper sit behind this line")
            .background(WindowProbe())
            .background(TwoFingerTap {})
        Sparkline().frame(height: 60)
    }
    .padding()
}
