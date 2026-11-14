// The focus outputs of a render: the map JSON, the overlay PNG and the stderr summary.
// `Renderer.render` calls `FocusOutputs.finish` after the screenshot is written; nothing here runs
// unless one of the runner flags asked for it.

@MainActor
enum FocusOutputs {
    /// Set by the runner's command line.
    static var request = FocusRequest()
    /// Added to the runner's JSON result line.
    static var payload: [String: Any] = [:]

    /// Writes the map JSON and the overlay PNG. `redraw` repaints the plain frame onto the surface
    /// (another overlay may have been drawn on it already).
    static func finish(engine: FocusEngine, config: RenderConfiguration, canvasSize: CGSize, scale: CGFloat, presses: [PressLog],
                       painter: Painter, surface: OpaquePointer, redraw: () -> Void) throws {
        guard request.wantsMap || !presses.isEmpty else { return }
        let snap = engine.snapshot
        let map = FocusMap(snap, initial: snap.index(of: engine.initialPath) ?? snap.initial, focused: snap.index(of: engine.focusedPath))
        if let path = request.mapPath {
            try AccessibilityOutputs.write(map.json(config: config, canvasSize: canvasSize, presses: presses).render() + "\n", to: path)
            payload["focusMap"] = path
        }
        if let path = request.overlayPath {
            redraw()
            FocusOverlay.draw(map, painter: painter, canvasSize: canvasSize, scale: scale)
            try AccessibilityOutputs.writePNG(surface: surface, to: path)
            payload["focusOverlay"] = path
        }
        var text = presses.map { "press \($0.press): \($0.note)" }
        if request.wantsMap { text.append(map.summaryText()) }
        if !text.isEmpty { FileHandle.standardError.write(Data((text.joined(separator: "\n") + "\n").utf8)) }
        var summary: [String: Any] = ["elements": snap.elements.count, "unreachable": map.paths.filter { $0 == nil }.count,
                                      "issues": map.issues.count]
        if let f = map.focused { summary["focused"] = snap.elements[f].id }
        payload["focus"] = summary
    }
}
