// `import AVFoundation`: players that never play, an audio session that accepts its settings, capture
// authorization not determined.
@_exported import Foundation
@_exported import CoreGraphics

public struct CMTime: Equatable, Hashable, Sendable {
    public var value: Int64
    public var timescale: Int32
    public init(value: Int64, timescale: Int32) { self.value = value; self.timescale = timescale }
    public init(seconds: Double, preferredTimescale: Int32) { self.init(value: Int64(seconds * Double(preferredTimescale)), timescale: preferredTimescale) }
    public var seconds: Double { timescale == 0 ? 0 : Double(value) / Double(timescale) }
    public static let zero = CMTime(value: 0, timescale: 1)
    public static let invalid = CMTime(value: 0, timescale: 0)
}
public func CMTimeMake(value: Int64, timescale: Int32) -> CMTime { CMTime(value: value, timescale: timescale) }
public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }

open class AVAsset: NSObject, @unchecked Sendable {}
open class AVURLAsset: AVAsset, @unchecked Sendable {
    public let url: URL
    public init(url URL: URL, options: [String: Any]? = nil) { url = URL; super.init() }
}
open class AVPlayerItem: NSObject, @unchecked Sendable {
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }
    public let asset: AVAsset
    open var status: Status { .unknown }
    open var duration: CMTime { .invalid }
    public init(url URL: URL) { asset = AVURLAsset(url: URL); super.init() }
    public init(asset: AVAsset) { self.asset = asset; super.init() }
    public static let didPlayToEndTimeNotification = Notification.Name("AVPlayerItemDidPlayToEndTimeNotification")
}
open class AVPlayer: NSObject, @unchecked Sendable {
    public enum TimeControlStatus: Int, Sendable { case paused, waitingToPlayAtSpecifiedRate, playing }
    open private(set) var currentItem: AVPlayerItem?
    open var rate: Float = 0
    open var volume: Float = 1
    open var isMuted = false
    open var timeControlStatus: TimeControlStatus { .paused }
    public override init() { super.init() }
    public init(url URL: URL) { currentItem = AVPlayerItem(url: URL); super.init() }
    public init(playerItem item: AVPlayerItem?) { currentItem = item; super.init() }
    open func play() {}
    open func pause() {}
    open func seek(to time: CMTime) {}
    open func seek(to time: CMTime) async -> Bool { true }
    open func currentTime() -> CMTime { .zero }
    open func replaceCurrentItem(with item: AVPlayerItem?) { currentItem = item }
    @discardableResult open func addPeriodicTimeObserver(forInterval interval: CMTime, queue: DispatchQueue?, using block: @escaping (CMTime) -> Void) -> Any { 0 }
    open func removeTimeObserver(_ observer: Any) {}
}
open class AVQueuePlayer: AVPlayer, @unchecked Sendable {
    public init(items: [AVPlayerItem]) { super.init(playerItem: items.first) }
}
open class AVPlayerLooper: NSObject, @unchecked Sendable {
    public init(player: AVQueuePlayer, templateItem itemToLoop: AVPlayerItem) { super.init() }
}
open class AVAudioPlayer: NSObject, @unchecked Sendable {
    open var volume: Float = 1
    open var numberOfLoops = 0
    open var isPlaying: Bool { false }
    public init(contentsOf url: URL) throws { super.init() }
    public init(data: Data) throws { super.init() }
    @discardableResult open func play() -> Bool { false }
    @discardableResult open func prepareToPlay() -> Bool { true }
    open func pause() {}
    open func stop() {}
}
open class AVAudioSession: NSObject, @unchecked Sendable {
    public struct Category: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "AVAudioSessionCategoryAmbient")
        public static let playback = Category(rawValue: "AVAudioSessionCategoryPlayback")
        public static let record = Category(rawValue: "AVAudioSessionCategoryRecord")
        public static let playAndRecord = Category(rawValue: "AVAudioSessionCategoryPlayAndRecord")
        public static let soloAmbient = Category(rawValue: "AVAudioSessionCategorySoloAmbient")
    }
    public struct Mode: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "AVAudioSessionModeDefault")
        public static let moviePlayback = Mode(rawValue: "AVAudioSessionModeMoviePlayback")
        public static let spokenAudio = Mode(rawValue: "AVAudioSessionModeSpokenAudio")
    }
    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1)
        public static let duckOthers = CategoryOptions(rawValue: 2)
    }
    private static let shared = AVAudioSession()
    open class func sharedInstance() -> AVAudioSession { shared }
    open private(set) var category = Category.soloAmbient
    open func setCategory(_ category: Category) throws { self.category = category }
    open func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws { self.category = category }
    open func setActive(_ active: Bool) throws {}
    open var isOtherAudioPlaying: Bool { false }
}
public enum AVAuthorizationStatus: Int, Sendable { case notDetermined, restricted, denied, authorized }
public struct AVMediaType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
    public static let audio = AVMediaType(rawValue: "soun")
}
open class AVCaptureDevice: NSObject, @unchecked Sendable {
    public class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus { .notDetermined }
    public class func requestAccess(for mediaType: AVMediaType) async -> Bool { false }
    public class func requestAccess(for mediaType: AVMediaType, completionHandler handler: @escaping (Bool) -> Void) { handler(false) }
    public class func `default`(for mediaType: AVMediaType) -> AVCaptureDevice? { nil }
}
