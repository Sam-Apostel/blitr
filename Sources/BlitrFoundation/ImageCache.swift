import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// `--image-cache <dir>`: images an app downloads while the network is allowed are kept in <dir>, and later
// renders without the network are answered from it, so a screen with remote photos looks the same offline,
// in CI or in a cloud session. Works at the URL loading layer, so `AsyncImage` and an app's own loaders both
// see it. Only responses whose type is an image are kept; everything else behaves as without the cache.

public enum _ImageCache {
    nonisolated(unsafe) static var directory: String?
    nonisolated(unsafe) static var online = false

    /// Called once by the runner before user code runs.
    public static func configure(directory: String, online: Bool) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        self.directory = directory
        self.online = online
        URLProtocol.registerClass(ImageCacheURLProtocol.self)
        #if canImport(Darwin)
        OfflineConfigurations.install(first: ImageCacheURLProtocol.self)
        #endif
    }

    /// A file name for a URL: FNV-1a of its text.
    static func key(_ url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    struct Entry: Codable { var url: String; var mimeType: String }

    static func lookup(_ url: URL) -> (data: Data, mimeType: String)? {
        guard let directory else { return nil }
        let base = directory + "/" + key(url)
        guard let meta = FileManager.default.contents(atPath: base + ".json"),
              let entry = try? JSONDecoder().decode(Entry.self, from: meta), entry.url == url.absoluteString,
              let data = FileManager.default.contents(atPath: base + ".data") else { return nil }
        return (data, entry.mimeType)
    }

    static func store(_ url: URL, data: Data, mimeType: String) {
        guard let directory else { return }
        let base = directory + "/" + key(url)
        let entry = Entry(url: url.absoluteString, mimeType: mimeType)
        guard let meta = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: URL(fileURLWithPath: base + ".data"), options: .atomic)
        try? meta.write(to: URL(fileURLWithPath: base + ".json"), options: .atomic)
    }
}

final class ImageCacheURLProtocol: URLProtocol, @unchecked Sendable {
    /// Marks the request the protocol makes itself, so it is not intercepted again.
    static let passThrough = "blitr.image-cache.pass-through"
    private var dataTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), ["http", "https"].contains(scheme),
              URLProtocol.property(forKey: passThrough, in: request) == nil else { return false }
        // Offline, answer what the cache has (anything else is left to the offline protocol); online, every
        // request goes through, so image responses can be kept.
        return _ImageCache.online || request.url.flatMap(_ImageCache.lookup) != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if let hit = _ImageCache.lookup(url) {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": hit.mimeType, "Content-Length": "\(hit.data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: hit.data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let forwarded = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.passThrough, in: forwarded)
        dataTask = URLSession.shared.dataTask(with: forwarded as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response {
                if let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let type = response.mimeType, type.hasPrefix("image/") {
                    _ImageCache.store(url, data: data, mimeType: type)
                }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        dataTask?.resume()
    }
    override func stopLoading() { dataTask?.cancel() }
}
