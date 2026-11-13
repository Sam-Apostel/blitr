// AsyncImage. Rendering is offline and single-frame, so a remote image is never loaded:
// the view shows what an app shows while loading (its placeholder / `.empty` phase).

public enum AsyncImagePhase: Sendable {
    case empty
    case success(Image)
    case failure(any Error)
    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }
    public var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

public struct AsyncImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    public init(url: URL?, scale: CGFloat = 1) where Content == _AsyncImagePlaceholder {
        self.url = url
        self.content = { _ in _AsyncImagePlaceholder() }
    }
    public init<I: View, P: View>(url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping (Image) -> I,
                                  @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalContent<I, P> {
        self.url = url
        self.content = { phase in
            if let image = phase.image { ViewBuilder.buildEither(first: content(image)) } else { ViewBuilder.buildEither(second: placeholder()) }
        }
    }
    public init(url: URL?, scale: CGFloat = 1, transaction: Transaction = Transaction(),
                @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        // A local file URL can be shown for real; anything remote stays in the loading phase.
        if let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            content(.success(Image(_file: url.path)))
        } else {
            content(.empty)
        }
    }
}

/// The default placeholder: a neutral fill, as on iOS.
public struct _AsyncImagePlaceholder: View {
    public var body: some View { Color(SystemColor.secondaryFill) }
}

extension Image {
    init(_file path: String) { self.init(source: .file(path)) }
    init(source: Source) {
        self.source = source
    }
}
