//
//  NetworkMonitor.swift
//  NeedleTailClient3
//
//  Created by Cole M on 4/26/22.
//

#if canImport(Network) && canImport(Combine)
import Foundation
import Network
import Combine

private final class NetworkPublisher: NSObject, ObservableObject {
    @Published var currentStatus: NWPath.Status = .unsatisfied
}

public final actor NetworkMonitor {
    
    @MainActor public let receiver = MonitorReceiver()
    private let monitorPath = NWPathMonitor()
    private var statusCancellable: Cancellable?
    fileprivate let networkPublisher = NetworkPublisher()
    
    public init() {}
    

    public func startMonitor() async {
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitorPath.start(queue: queue)
        await monitor()
    }
    
    public func monitor() async {
        statusCancellable = networkPublisher.publisher(for: \.currentStatus) as? Cancellable
        monitorPath.pathUpdateHandler = { [weak self] path in
            guard let strongSelf = self else { return }
            strongSelf.networkPublisher.currentStatus = path.status
        }
    }
    
    public func cancelMonitor() {
        monitorPath.cancel()
        statusCancellable = nil
    }
    
    
    @MainActor
    public func getStatus() async {
            for await status in networkPublisher.$currentStatus.values {
                receiver.updateStatus.send(status)
            }
    }
}


public class MonitorReceiver {
    public let updateStatus = PassthroughSubject<NWPath.Status, Never>()
}
#endif
