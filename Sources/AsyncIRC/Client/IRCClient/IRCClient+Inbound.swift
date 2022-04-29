//
//  IRCClient+Inbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import NeedleTailHelpers

extension IRCClient {

    /// This is where we receive all messages from server in the client
    /// - Parameter message: Our IRCMessage that we received
    @NeedleTailKitActor
    func processReceivedMessages(_ message: IRCMessage) async {
        if case .registering = userState.state {
            if message.command.signalsSuccessfulRegistration {
                await handleRegistrationDone()
            }
            
            if case .numeric(.errorNicknameInUse, _) = message.command {
                return await handleRegistrationFailed(with: message)
            }
            else if message.command.isErrorReply {
                return await handleRegistrationFailed(with: message)
            }
        }
        
        do {
            try await irc_msgSend(message)
        } catch {
            logger.error("handle dispatcher error: \(error)")
        }
    }
    
    
    public func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws {
        await delegate?.client(self, notice: message, for: recipients)
    }
    
    @NeedleTailKitActor
    public func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?,
        userStatus: UserStatus
    ) async throws {
        print("SENDER_____", sender)
        guard let sender = sender else { // should never happen
            assertionFailure("got empty message sender!")
            return
        }
        await delegate?.client(self, message: message, from: sender, for: recipients)
    }
    
    public func doNick(_ newNick: NeedleTailNick) async throws {
        switch userState.state {
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            userState.transition(to: .registering(channel: channel, nick: newNick, userInfo: info))
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            userState.transition(to: .registered(channel: channel, nick: newNick, userInfo: info))
            
        default: return // hmm
        }
        await delegate?.client(self, changedNickTo: newNick)
    }
    
    
    public func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        guard let myNick = self.nick, myNick == nick else {
            return
        }
        
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            await delegate?.client(self, changedUserModeTo: newMode)
        }
    }
    
    public func doPing(_ server: String, server2: String? = nil) async throws {
        let msg: IRCMessage
        
        msg = IRCMessage(origin: origin, // probably wrong
                         command: .PONG(server: server, server2: server))
        await sendAndFlushMessage(msg, chatDoc: nil)
    }
}
