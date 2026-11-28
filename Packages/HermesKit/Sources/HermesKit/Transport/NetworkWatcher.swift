import Foundation
import Network

/// The device's way onto the network, from Network framework's path monitor.
struct NetworkPath: Equatable, Sendable {
    /// There's a route out at all.
    var isSatisfied: Bool
    /// Which interface carries traffic, e.g. Wi-Fi then cellular. When it changes, a socket opened
    /// over the old one may be dead without saying so.
    var route: String

    init(isSatisfied: Bool, route: String) {
        self.isSatisfied = isSatisfied
        self.route = route
    }

    init(_ path: NWPath) {
        isSatisfied = path.status == .satisfied
        let kinds: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "wifi"), (.cellular, "cellular"), (.wiredEthernet, "wired"), (.other, "other"),
        ]
        let used = kinds.filter { path.usesInterfaceType($0.0) }.map(\.1)
        route = ([path.availableInterfaces.first?.name ?? ""] + used).joined(separator: ",")
    }
}

/// Hands each change of `NetworkPath` to the main actor until it's released.
@MainActor
final class NetworkWatcher {
    private let monitor = NWPathMonitor()

    init(changed: @escaping @MainActor (NetworkPath) -> Void) {
        monitor.pathUpdateHandler = { path in
            let network = NetworkPath(path)
            Task { @MainActor in changed(network) }
        }
        monitor.start(queue: DispatchQueue(label: "UsualBot.network"))
    }

    deinit {
        monitor.cancel()
    }
}
