//
//  IRCClient+Outbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import NeedleTailHelpers
import CypherMessaging

extension IRCClient {
    
    /// This method is how all client messages get sent through the client to the server. This is the where they leave the Client.
    /// - Parameters:
    ///   - message: Our IRCMessage
    ///   - chatDoc: Not needed/used for clients and shouldn't be.
    public func sendAndFlushMessage(_ message: IRCMessage, chatDoc: ChatDocument?) async {
        do {
            try await channel?.writeAndFlush(message)
        } catch {
            logger.error("\(error)")
        }
    }
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @NeedleTailActor
    func registerNeedletailSession(_ regPacket: String?) async {
        guard case .registering(_, let nick, let user) = userState.state else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        if let pwd = options.password {
            await createNeedleTailMessage(.otherCommand("PASS", [ pwd ]))
        }
        
        if let regPacket = regPacket {
            let tag = IRCTags(key: "registrationPacket", value: regPacket)
            await createNeedleTailMessage(.NICK(nick), tags: [tag])
        } else {
            await createNeedleTailMessage(.NICK(nick))
        }
        await createNeedleTailMessage(.USER(user))
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
        @KeyBundleActor
        public func readKeyBundle(_ packet: String) async -> UserConfig? {
            await sendKeyBundleRequest(.otherCommand("READKEYBNDL", [packet]))
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
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    @NeedleTailActor
    public func changeNick(_ nick: NeedleTailNick) async {
        await createNeedleTailMessage(.NICK(nick))
    }
    
    @NeedleTailActor
    func _resubscribe() {
        if !subscribedChannels.isEmpty {
            // TODO: issues JOIN commands
        }
    }
    @NeedleTailActor
    public func sendPrivateMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]? = nil) async {
        await sendIRCMessage(message.base64EncodedString(), to: recipient, tags: tags)
    }
}
