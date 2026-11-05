import Foundation
import Network
import Observation

@MainActor @Observable
final class BankNetworkStatus {
    private(set) var isOffline = false
    private(set) var revision = 0
    private let monitor = NWPathMonitor()
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            isOffline = ProcessInfo.processInfo.arguments.contains("--offline-bank")
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOffline != offline else { return }
                self.isOffline = offline; self.revision += 1
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.sean.tender.bank-network"))
    }
    deinit { monitor.cancel() }
}
