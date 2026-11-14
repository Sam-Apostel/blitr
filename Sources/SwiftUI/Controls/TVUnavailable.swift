// Controls that do not exist on tvOS (Apple's documentation lists no tvOS availability for them). They
// keep compiling here so a shared iOS/tvOS file still renders, but a real tvOS build would fail, so the
// first use while rendering tvOS warns. Each type calls this from a stored property's initial value,
// which runs in every initializer.

@MainActor
func tvOSUnavailable(_ name: String) -> Bool {
    if RenderedPlatform.platform == .tvOS {
        Runtime.current?.warn("\(name) is not available on tvOS: a real tvOS build fails to compile. It is drawn with its iOS look here")
    }
    return true
}
