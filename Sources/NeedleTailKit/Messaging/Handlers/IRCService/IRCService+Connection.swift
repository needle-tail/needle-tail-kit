//
//  IRCService+Connection.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import NeedleTailHelpers

extension IRCService {
    
    @NeedleTailActor
    func attemptConnection(_ regPacket: String? = nil) async throws {
        switch transportState.current {
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            break
        case .connecting:
            break
        case .online:
            break
        case .suspended, .offline:
            transportState.transition(to: .connecting)
            try await client?.startClient(regPacket)
        case .disconnect:
            break
        case .error:
            break
        case .quit:
            break
        }
    }

    @NeedleTailActor
    func attemptDisconnect(_ isSuspending: Bool) async {
        if isSuspending {
            transportState.transition(to: .suspended)
        }
        switch transportState.current {
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            break
        case .connecting:
            break
        case .online:
            await client?.disconnect()
            client = nil
            authenticated = .unauthenticated
        case .suspended, .offline:
            return
        case .disconnect:
            break
        case .error:
            break
        case .quit:
            break
        }
    }
}
