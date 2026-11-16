// AsyncImage. A `file:` URL is shown at once. A remote image is loaded while the frame settles when the
// render may use the network (`--allow-network`), like a `.task`; offline, the view shows what an app shows
// while loading (its placeholder / `.empty` phase).

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
    var scale: CGFloat = 1
    let content: (AsyncImagePhase) -> Content
    @State private var loaded: _AsyncImageLoad?

    public init(url: URL?, scale: CGFloat = 1) where Content == _ConditionalContent<Image, _AsyncImagePlaceholder> {
        self.url = url
        self.scale = scale
        self.content = { phase in
            if let image = phase.image { ViewBuilder.buildEither(first: image) } else { ViewBuilder.buildEither(second: _AsyncImagePlaceholder()) }
        }
    }
    public init<I: View, P: View>(url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping (Image) -> I,
                                  @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalContent<I, P> {
        self.url = url
        self.scale = scale
        self.content = { phase in
            if let image = phase.image { ViewBuilder.buildEither(first: content(image)) } else { ViewBuilder.buildEither(second: placeholder()) }
        }
    }
    public init(url: URL?, scale: CGFloat = 1, transaction: Transaction = Transaction(),
                @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.scale = scale
        self.content = content
    }

    public var body: some View {
        if let url, url.isFileURL {
            content(_AsyncImageLoad.local(url, scale: scale).phase)
        } else {
            // Read on the main actor: the render's configuration is not visible from the task.
            let online = _currentConfiguration().allowsNetwork || _currentConfiguration().imageCacheDirectory != nil
            content(loaded?.url == url ? loaded!.phase : .empty)
                .task(id: url) {
                    guard let url, online else { return }
                    let result = await _AsyncImageLoad.fetch(url, scale: scale)
                    await MainActor.run { loaded = result }
                }
        }
    }
}

/// What an `AsyncImage` loaded: an image file in the cache directory, or the error.
struct _AsyncImageLoad: @unchecked Sendable {
    var url: URL?
    var phase: AsyncImagePhase

    /// A file the decoder reads at `scale` pixels per point (`name@2x.ext`, see `Image.resolve`).
    static func local(_ url: URL, scale: CGFloat) -> _AsyncImageLoad {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return _AsyncImageLoad(url: url, phase: .failure(URLError(.fileDoesNotExist)))
        }
        guard scale == 2 || scale == 3 else { return _AsyncImageLoad(url: url, phase: .success(Image(_file: url.path))) }
        let link = cacheDirectory + "/\(key(url))@\(Int(scale))x.\(url.pathExtension.isEmpty ? "img" : url.pathExtension)"
        if !FileManager.default.fileExists(atPath: link) { try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: url.path) }
        return _AsyncImageLoad(url: url, phase: .success(Image(_file: link)))
    }

    static func fetch(_ url: URL, scale: CGFloat) async -> _AsyncImageLoad {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return _AsyncImageLoad(url: url, phase: .failure(URLError(.badServerResponse)))
            }
            let suffix = scale == 2 || scale == 3 ? "@\(Int(scale))x" : ""
            let path = cacheDirectory + "/\(key(url))\(suffix).img"
            try data.write(to: URL(fileURLWithPath: path))
            guard Bitmap(path: path, scale: 1) != nil else {
                return _AsyncImageLoad(url: url, phase: .failure(URLError(.cannotDecodeContentData)))
            }
            return _AsyncImageLoad(url: url, phase: .success(Image(_file: path)))
        } catch {
            return _AsyncImageLoad(url: url, phase: .failure(error))
        }
    }

    static let cacheDirectory: String = {
        let path = NSTemporaryDirectory() + "blitr-images-\(getpid())"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    /// A file name for a URL (FNV-1a of its text).
    static func key(_ url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
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
