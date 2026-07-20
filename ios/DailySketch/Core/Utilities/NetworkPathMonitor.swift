import Foundation
import Network
import Observation

@MainActor
protocol NetworkMonitoring: AnyObject {
    var isOnline: Bool { get }
}

@MainActor
@Observable
final class NetworkPathMonitorService: NetworkMonitoring {
    private(set) var isOnline = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.example.dailysketch.network-path")

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

@MainActor
@Observable
final class FixedNetworkMonitor: NetworkMonitoring {
    var isOnline: Bool

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }
}
