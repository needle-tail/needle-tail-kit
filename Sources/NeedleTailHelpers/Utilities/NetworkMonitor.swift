//
//  NetworkMonitor.swift
//  NeedleTailClient3
//
//  Created by Cole M on 4/26/22.
//

#if canImport(Network)
import Network
#if canImport(SwiftUI)
import SwiftUI
#endif

public final class NetworkMonitor {
    public static let shared = NetworkMonitor()
    private let monitorPath = NWPathMonitor()
    private var isSet = false
    
#if (os(macOS) || os(iOS))
    @Published public var currentStatus: NWPath.Status = .unsatisfied
#endif
    
    public var currentStatusStream: AsyncStream<NWPath.Status>?
    public init() {}


    public func startMonitor() async {
        if !isSet {
            let queue = DispatchQueue(label: "network-monitor")
            monitorPath.start(queue: queue)
            await monitor()
        }
    }
    
    public func monitor() async {
        let currentStatusStream = AsyncStream<NWPath.Status> { continuation in
            monitorPath.pathUpdateHandler = { path in
                continuation.yield(path.status)
            }
            continuation.onTermination = { status in
                print("Monitor Stream Terminated with status:", status)
            }
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                try Task.checkCancellation()
                for await status in currentStatusStream {
                    group.addTask {
                        self.currentStatus = status
                    }
                }
                group.cancelAll()
            }
        } catch {
            print(error)
        }
    }
    
    public func cancelMonitor() {
        monitorPath.cancel()
    }
}
#if (os(macOS) || os(iOS))
extension NetworkMonitor: ObservableObject {}
#endif
#endif
