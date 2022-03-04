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
    private func handleAccountChange() async {
        await self.connectIfNecessary()
    }
    
    private func connectIfNecessary(_ regPacket: String? = nil) async {
        guard case .offline = userState.state else { return }
        guard let options = activeClientOptions else { return }
        guard let store = store else { return }
        self.client = IRCClient(options: options, store: store)
        self.client?.delegate = self
        userState.transition(to: .connecting)
        do {
            _ = try await client?.connecting(regPacket)
                self.authenticated = .authenticated
        } catch {
            self.authenticated = .authenticationFailure
               await self.connectIfNecessary(regPacket)
        }
    }

    // MARK: - Lifecycle
    public func resume(_ regPacket: String? = nil) async {
        await connectIfNecessary(regPacket)
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
