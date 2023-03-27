//
//  NetworkMonitor.swift
//  NeedleTailClient3
//
//  Created by Cole M on 4/26/22.
//

#if canImport(Network) && canImport(Combine)
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
    
    public init() {
        statusCancellable = networkPublisher.publisher(for: \.currentStatus) as? Cancellable
    }


    public func startMonitor() async {
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitorPath.start(queue: queue)
        await monitor()
    }
    
    public func monitor() async {
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
                receiver.updateStatus = status
            }
    }
}


public class MonitorReceiver: ObservableObject {
    @MainActor
    @Published
    public var statusArray = [NWPath.Status]()
    
    @Published
    public var updateStatus: NWPath.Status = .requiresConnection {
        didSet {
             Task {
                await updateStatus()
            }
        }
    }
    
    @MainActor
    func updateStatus() async {
        statusArray.removeAll()
        for await status in $updateStatus.values {
            statusArray.append(status)
            break
        }
    }
    
}
#endif
