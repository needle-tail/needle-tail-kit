//
//  NetworkMonitor.swift
//  NeedleTailClient3
//
//  Created by Cole M on 4/26/22.
//

#if canImport(Network) && canImport(Combine)
import Network
import Combine

public final class NetworkMonitor: NSObject, ObservableObject {
    public static let shared = NetworkMonitor()
    private let monitorPath = NWPathMonitor()
    private var statusCancellable: Cancellable?
    private var isSet = false
    @Published public var currentStatus: NWPath.Status = .unsatisfied
    
    public override init() {
        super.init()
        statusCancellable = self.publisher(for: \.currentStatus) as? Cancellable
    }


    public func startMonitor() async {
        if !isSet {
            let queue = DispatchQueue(label: "network-monitor")
            monitorPath.start(queue: queue)
            monitor()
        }
    }
    
    public func monitor() {
        monitorPath.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentStatus = path.status
            }
        }
    }
    
    public func cancelMonitor() {
        monitorPath.cancel()
        statusCancellable = nil
    }
}
#endif
