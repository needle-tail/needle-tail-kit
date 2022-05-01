//
//  IRCClient+Outbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import NeedleTailHelpers

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
        print("REGEISTERED___")
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    @KeyBundleActor
    public func readKeyBundle(_ packet: String) async {
        await sendKeyBundleRequest(.otherCommand("READKEYBNDL", [packet]))
    }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    @NeedleTailActor
    public func changeNick(_ nick: NeedleTailNick) async {
        await createNeedleTailMessage(.NICK(nick))
    }
    
    func _resubscribe() {
        if !subscribedChannels.isEmpty {
            // TODO: issues JOIN commands
        }
    }
    @NeedleTailActor
    public func sendPrivateMessage(_ message: String, to recipient: IRCMessageRecipient, tags: [IRCTags]? = nil) async {
        await sendIRCMessage(message, to: recipient, tags: tags)
    }
}
