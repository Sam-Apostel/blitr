// `import PhotosUI`: PhotosPicker is drawn as its label, in a button (as on iOS). Picked items never
// arrive: the selection stays as the app set it, and loading an item's data gives nil.
@_exported import SwiftUI
@_exported import UniformTypeIdentifiers
import UIKit

public struct PHPickerFilter: Hashable, Sendable {
    let name: String
    public static let images = PHPickerFilter(name: "images")
    public static let videos = PHPickerFilter(name: "videos")
    public static let livePhotos = PHPickerFilter(name: "livePhotos")
    public static let screenshots = PHPickerFilter(name: "screenshots")
    public static let screenRecordings = PHPickerFilter(name: "screenRecordings")
    public static let panoramas = PHPickerFilter(name: "panoramas")
    public static let bursts = PHPickerFilter(name: "bursts")
    public static let depthEffectPhotos = PHPickerFilter(name: "depthEffectPhotos")
    public static let spatialMedia = PHPickerFilter(name: "spatialMedia")
    public static func any(of subfilters: [PHPickerFilter]) -> PHPickerFilter { PHPickerFilter(name: "any") }
    public static func all(of subfilters: [PHPickerFilter]) -> PHPickerFilter { PHPickerFilter(name: "all") }
    public static func not(_ filter: PHPickerFilter) -> PHPickerFilter { PHPickerFilter(name: "not") }
}

public struct PhotosPickerItem: Equatable, Hashable, Sendable, Transferable {
    public enum EncodingDisambiguationPolicy: Hashable, Sendable { case automatic, current, compatible }
    public let itemIdentifier: String?
    public var supportedContentTypes: [UTType] { [.image] }
    public init(itemIdentifier: String) { self.itemIdentifier = itemIdentifier }
    /// Nothing was picked, so there is nothing to load.
    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? { nil }
    public func loadTransferable<T: Transferable>(type: T.Type, completionHandler: @escaping (Result<T?, Error>) -> Void) -> Progress {
        completionHandler(.success(nil))
        return Progress(totalUnitCount: 0)
    }
}

public struct PhotosPickerSelectionBehavior: Hashable, Sendable {
    let raw: Int
    public static let `default` = PhotosPickerSelectionBehavior(raw: 0)
    public static let ordered = PhotosPickerSelectionBehavior(raw: 1)
    public static let continuous = PhotosPickerSelectionBehavior(raw: 2)
    public static let continuousAndOrdered = PhotosPickerSelectionBehavior(raw: 3)
}
public struct PhotosPickerStyle: Hashable, Sendable {
    let raw: Int
    public static let presentation = PhotosPickerStyle(raw: 0)
    public static let inline = PhotosPickerStyle(raw: 1)
    public static let compact = PhotosPickerStyle(raw: 2)
}
public struct PHPickerCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let search = PHPickerCapabilities(rawValue: 1)
    public static let stagingArea = PHPickerCapabilities(rawValue: 2)
    public static let collectionNavigation = PHPickerCapabilities(rawValue: 4)
    public static let selectionActions = PHPickerCapabilities(rawValue: 8)
    public static let sensitivityAnalysisIntervention = PHPickerCapabilities(rawValue: 16)
}

public struct PhotosPicker<Label: View>: View {
    let label: Label
    public init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic, @ViewBuilder label: () -> Label) {
        self.label = label()
    }
    public init(selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil, selectionBehavior: PhotosPickerSelectionBehavior = .default,
                matching filter: PHPickerFilter? = nil, preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                @ViewBuilder label: () -> Label) {
        self.label = label()
    }
    public var body: some View { Button(action: {}) { label } }
}
extension PhotosPicker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        label = Text(titleKey)
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                   preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        label = Text(title)
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        label = Text(titleKey)
    }
}

extension View {
    /// The picker sheet is not shown (`isPresented` is left as the app set it).
    public func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                             preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        if isPresented.wrappedValue { ShimDiagnostics.warn("photosPicker(isPresented:) is presented: the photo picker sheet is not drawn") }
        return self
    }
    public func photosPicker(isPresented: Binding<Bool>, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                             selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                             preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        if isPresented.wrappedValue { ShimDiagnostics.warn("photosPicker(isPresented:) is presented: the photo picker sheet is not drawn") }
        return self
    }
    public func photosPickerStyle(_ style: PhotosPickerStyle) -> some View { self }
    public func photosPickerAccessoryVisibility(_ visibility: Visibility, edges: Edge.Set = .all) -> some View { self }
    public func photosPickerDisabledCapabilities(_ disabledCapabilities: PHPickerCapabilities) -> some View { self }
}

// MARK: - UIKit picker

public struct PHPickerConfiguration: Sendable {
    public enum AssetRepresentationMode: Int, Sendable { case automatic, current, compatible }
    public enum Selection: Int, Sendable { case `default`, ordered, continuous, continuousAndOrdered }
    public var filter: PHPickerFilter?
    public var selectionLimit = 1
    public var preferredAssetRepresentationMode = AssetRepresentationMode.automatic
    public var selection = Selection.default
    public var preselectedAssetIdentifiers: [String] = []
    public init() {}
    public init(photoLibrary: AnyObject) {}
}
public struct PHPickerResult: Hashable, @unchecked Sendable {
    public let itemProvider: NSItemProvider
    public let assetIdentifier: String?
}
public protocol PHPickerViewControllerDelegate: AnyObject {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult])
}
open class PHPickerViewController: UIViewController {
    public let configuration: PHPickerConfiguration
    open weak var delegate: PHPickerViewControllerDelegate?
    public init(configuration: PHPickerConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { configuration = PHPickerConfiguration(); super.init(coder: coder) }
    open func deselectAssets(withIdentifiers identifiers: [String]) {}
}
