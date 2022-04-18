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
    
//    
//    internal func publishKeyBundle(_ keyBundle: String) async {
//        await client?.publishKeyBundle(keyBundle)
//    }
    
    func readKeyBundle(_ packet: String) async -> UserConfig? {
        await client?.readKeyBundle(packet)
        let date = RunLoop.timeInterval(10)
        var canRun = false
        
        repeat {
            canRun = true
            if userConfig != nil {
                canRun = false
            }
            /// We just want to run a loop until the userConfig contains a value or stop on the timeout
        } while await RunLoop.execute(date, canRun: canRun)
        return userConfig
    }
    
//    func registerAPN(_ packet: String) async {
//        await client?.registerAPN(packet)
//    }

    //MARK: - CypherMessageAPI
    public func sendMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]?) async throws -> Bool {
        //        guard case .online = userState.state else { return false }
        await client?.sendMessage(message.base64EncodedString(), to: recipient, tags: tags)
        return true
    }
}
