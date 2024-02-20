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

public actor NetworkMonitor {
    static public let shared = NetworkMonitor()
    private let monitorPath = NWPathMonitor()
    private var isSet = false
    
    public var currentStatusStream: AsyncStream<NWPath.Status>?
    public init() {}

    @MainActor
    public var status: NWPath.Status = .unsatisfied
    public func startMonitor() async {
        if !isSet {
            let queue = DispatchQueue(label: "network-monitor")
            monitorPath.start(queue: queue)
            await monitor()
        }
    }
    @MainActor
    func setTask(status: NWPath.Status ) {
        self.status = status
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
        self.currentStatusStream = currentStatusStream
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                try Task.checkCancellation()
                for await s in currentStatusStream {
                    group.addTask {
                        await self.setTask(status: s)
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
#endif
