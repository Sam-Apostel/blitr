// `import Network`: path monitoring reports a satisfied Wi-Fi path, as on a connected device. Connections
// and listeners exist for source compatibility and never become ready.
@_exported import Foundation

public struct NWInterface: Hashable, Sendable {
    public enum InterfaceType: Hashable, Sendable { case other, wifi, cellular, wiredEthernet, loopback }
    public let name: String
    public let type: InterfaceType
    public let index: Int
}

public struct NWPath: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case satisfied, unsatisfied, requiresConnection }
    public enum UnsatisfiedReason: Equatable, Sendable { case notAvailable, cellularDenied, wifiDenied, localNetworkDenied, vpnInactive }
    public let status: Status
    public var unsatisfiedReason: UnsatisfiedReason { .notAvailable }
    public let availableInterfaces: [NWInterface]
    public var isExpensive: Bool { false }
    public var isConstrained: Bool { false }
    public var supportsIPv4: Bool { true }
    public var supportsIPv6: Bool { true }
    public var supportsDNS: Bool { true }
    public var gateways: [NWEndpoint] { [] }
    public func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool { availableInterfaces.contains { $0.type == type } }
    static let connected = NWPath(status: .satisfied, availableInterfaces: [NWInterface(name: "en0", type: .wifi, index: 1)])
}

public final class NWPathMonitor: @unchecked Sendable {
    public var pathUpdateHandler: (@Sendable (NWPath) -> Void)?
    public private(set) var queue: DispatchQueue?
    public var currentPath: NWPath { .connected }
    public init() {}
    public init(requiredInterfaceType: NWInterface.InterfaceType) {}
    public init(prohibitedInterfaceTypes: [NWInterface.InterfaceType]) {}
    /// Reports the (satisfied) path once, on the queue.
    public func start(queue: DispatchQueue) {
        self.queue = queue
        let handler = pathUpdateHandler
        queue.async { handler?(.connected) }
    }
    public func cancel() {}
}
extension NWPathMonitor: AsyncSequence {
    public typealias Element = NWPath
    public struct Iterator: AsyncIteratorProtocol {
        var sent = false
        public mutating func next() async -> NWPath? {
            if sent { return nil }
            sent = true
            return .connected
        }
    }
    public func makeAsyncIterator() -> Iterator { Iterator() }
}

public enum NWEndpoint: Hashable, Sendable {
    public struct Host: Hashable, Sendable, ExpressibleByStringLiteral {
        let name: String
        public init(_ name: String) { self.name = name }
        public init(stringLiteral value: String) { name = value }
    }
    public struct Port: Hashable, Sendable, ExpressibleByIntegerLiteral {
        public let rawValue: UInt16
        public init?(rawValue: UInt16) { self.rawValue = rawValue }
        public init(integerLiteral value: UInt16) { rawValue = value }
    }
    case hostPort(host: Host, port: Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    case url(URL)
}
public final class NWParameters: @unchecked Sendable {
    public static var tcp: NWParameters { NWParameters() }
    public static var udp: NWParameters { NWParameters() }
    public static var tls: NWParameters { NWParameters() }
    public init() {}
}
public enum NWError: Error, Sendable { case posix(Int32), dns(Int32), tls(Int32) }
public final class NWConnection: @unchecked Sendable {
    public enum State: Sendable { case setup, waiting(NWError), preparing, ready, failed(NWError), cancelled }
    public var stateUpdateHandler: (@Sendable (State) -> Void)?
    public private(set) var state = State.setup
    public init(to endpoint: NWEndpoint, using parameters: NWParameters) {}
    public init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters) {}
    public func start(queue: DispatchQueue) {}
    public func cancel() {}
}
