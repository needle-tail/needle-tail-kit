//
//  IRCService+Connection.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import NeedleTailHelpers

extension IRCService {
    
    @NeedleTailKitActor
    func attemptConnection(_ regPacket: String? = nil) async throws {
        userState.transition(to: .connecting)
        _ = try await client?.startClient(regPacket)
    }

    func attemptDisconnect() async {
        defer { userState.transition(to: .suspended) }
        switch userState.state {
        case .suspended, .offline:
            return
        case .connecting, .online:
            await client?.disconnect()
        default:
            break
        }
    }
}
