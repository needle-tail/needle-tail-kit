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
    private var isSet = false
    
    public init() {
        statusCancellable = networkPublisher.publisher(for: \.currentStatus) as? Cancellable
    }


    public func startMonitor() async {
        if !isSet {
            let queue = DispatchQueue(label: "network-monitor")
            monitorPath.start(queue: queue)
            await monitor()
        }
    }
    
    public func monitor() async {
        monitorPath.pathUpdateHandler = { [weak self] path in
            guard let strongSelf = self else { return }
//            path.use(nw_protocol_metadata(nw_protocol_copy_ip_definition(.ipv4)))
//
//            path.necp_verdict { verdict in
//                switch verdict {
//                case .needRules:
//                    nw_path_necp_start_transaction(path.necp_handle)
//                    nw_path_necp_use_as_policy_result(path.necp_handle)
//                    let status = nw_path_necp_check_for_updates(path.necp_handle) // Check for updates
//                    if status < 0 {
//                        print("Failed to update policy rules: \(status)")
//                    }
//                default: break
//                }
//            }
//
            
            
            strongSelf.networkPublisher.currentStatus = path.status
        }
    }
    
    public func cancelMonitor() {
        monitorPath.cancel()
        statusCancellable = nil
    }

    public func getStatus() async {
        if networkPublisher.currentStatus == .satisfied && !isSet {
            isSet = true
            for await status in networkPublisher.$currentStatus.values {
                receiver.updateStatus = status
            }
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
             Task { @MainActor in
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
