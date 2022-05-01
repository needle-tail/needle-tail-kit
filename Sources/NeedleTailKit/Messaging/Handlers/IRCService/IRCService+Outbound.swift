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
    
//TODO: We cannot use an actore to send a budle and wait for the read because our call will never finish and let go of the suspension in order to process the incoming packet.
    @KeyBundleActor
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
        } while await RunLoop.execute(date, ack: acknowledgment, canRun: canRun)
        assert(userConfig != nil, "User Config is nil")
        return userConfig
    }


    //TODO: Need to work out multiple recipients. Do we want an array or a variatic expression?
    @NeedleTailActor
    public func sendNeedleTailMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]?) async throws {
        guard userState.state == .online else { return }
        await client?.sendPrivateMessage(message.base64EncodedString(), to: recipient, tags: tags)
    }
}
