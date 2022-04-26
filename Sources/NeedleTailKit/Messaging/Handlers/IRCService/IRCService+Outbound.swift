//
//  IRCService+Outbound.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging
import AsyncIRC
import NeedleTailHelpers

//MARK: - Outbound
extension IRCService {
    
    func readKeyBundle(_ packet: String) async -> UserConfig? {
        await client?.readKeyBundle(packet)
        let date = RunLoop.timeInterval(1)
        var canRun = false
        
        repeat {
            canRun = true
            if userConfig != nil {
                canRun = false
            }
            /// We just want to run a loop until the userConfig contains a value or stop on the timeout
        } while await RunLoop.execute(date, ack: acknowledgment, canRun: canRun)
        return userConfig
    }


    //MARK: - CypherMessageAPI
    public func sendMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]?) async throws -> Bool {
        //        guard case .online = userState.state else { return false }
        await client?.sendMessage(message.base64EncodedString(), to: recipient, tags: tags)
        return true
    }
}
