////
////  IRCService+Outbound.swift
////  
////
////  Created by Cole M on 3/4/22.
////
//
//import Foundation
//import CypherMessaging
//import AsyncIRC
//import NeedleTailHelpers
//
////MARK: - Outbound
//extension IRCService {
//    //TODO: Need to work out multiple recipients. Do we want an array or a variatic expression?
//    @NeedleTailActor
//    public func sendNeedleTailMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]?) async throws {
////        guard userState.state == .online else { return }
//        print("Current state", userState.state)
//        await client?.sendPrivateMessage(message.base64EncodedString(), to: recipient, tags: tags)
//    }
//}
