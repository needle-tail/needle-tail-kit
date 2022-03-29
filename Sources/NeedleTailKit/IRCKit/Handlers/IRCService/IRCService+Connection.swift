//
//  File.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import AsyncIRC

extension IRCService {
    
    
    // MARK: - Connection
    private func handleAccountChange() async throws {
        try await self.connectIfNecessary()
    }
    
    private func connectIfNecessary(_ regPacket: String? = nil) async throws {
        guard case .offline = userState.state else { return }
        guard let options = activeClientOptions else { return }
        self.client = IRCClient(options: options)
        self.client?.delegate = self
        userState.transition(to: .connecting)
        _ = try await client?.connecting(regPacket)
    }


    // MARK: - Lifecycle
    public func resume(_ regPacket: String? = nil) async throws {
        try await connectIfNecessary(regPacket)
    }
    
    
    public func suspend() async {
        defer { userState.transition(to: .suspended) }
        switch userState.state {
        case .suspended, .offline:
            return
        case .connecting, .online:
            await client?.disconnect()
        }
    }
    
    public func close() async {
        await client?.disconnect()
    }
}
