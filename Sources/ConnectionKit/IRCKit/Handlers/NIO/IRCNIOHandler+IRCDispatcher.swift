//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIOIRC

extension IRCNIOHandler : IRCDispatcher {
    
    public func irc_msgSend(_ message: NIOIRC.IRCMessage) throws {
        do {
            return try irc_defaultMsgSend(message)
        }
        catch let error as IRCDispatcherError {
            guard case .doesNotRespondTo = error else { throw error }
        }
        catch { throw error }
        
        switch message.command {
        /* Message of the Day coalescing */
        case .numeric(.replyMotDStart, let args):
            messageOfTheDay = (args.last ?? "") + "\n"
        case .numeric(.replyMotD, let args):
            messageOfTheDay += (args.last ?? "") + "\n"
        case .numeric(.replyEndOfMotD, _):
            if !messageOfTheDay.isEmpty {
                delegate?.client(self, messageOfTheDay: messageOfTheDay)
            }
            messageOfTheDay = ""
            
        /* name reply */
        // <IRCCmd: 353 args=Guest1,=,#ZeeQL,Guest1> localhost -
        // <IRCCmd: 366 args=Guest1,#ZeeQL,End of /NAMES list> localhost -
        case .numeric(.replyNameReply, _ /*let args*/):
            #if false
            // messageOfTheDay += (args.last ?? "") + "\n"
            #else
            break
            #endif
        case .numeric(.replyEndOfNames, _):
            #if false
            if !messageOfTheDay.isEmpty {
                delegate?.client(self, messageOfTheDay: messageOfTheDay)
            }
            messageOfTheDay = ""
            #else
            break
            #endif
            
        case .numeric(.replyTopic, let args):
            // :localhost 332 Guest31 #NIO :Welcome to #nio!
            guard args.count > 2, let channel = IRCChannelName(args[1]) else {
                return print("ERROR: topic args incomplete:", message)
            }
            delegate?.client(self, changeTopic: args[2], of: channel)
            
        /* join/part, we need the origin here ... (fix dispatcher) */
        
        case .JOIN(let channels, _):
            guard let origin = message.origin, let user = IRCUserID(origin) else {
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            delegate?.client(self, user: user, joined: channels)
            
        case .PART(let channels, let leaveMessage):
            guard let origin = message.origin, let user = IRCUserID(origin) else {
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            delegate?.client(self, user: user, left: channels, with: leaveMessage)
            
        /* unexpected stuff */
        
        case .otherNumeric(let code, let args):
            #if false
            print("OTHER NUM:", code, args)
            #endif
            delegate?.client(self, received: message)
            
        default:
            #if false
            print("OTHER COMMAND:", message.command,
                  message.origin ?? "-", message.target ?? "-")
            #endif
            delegate?.client(self, received: message)
        }
    }
    
    open func doNotice(recipients: [ IRCMessageRecipient ], message: String) throws {
        delegate?.client(self, notice: message, for: recipients)
    }
    
    open func doMessage(sender     : IRCUserID?,
                        recipients : [ IRCMessageRecipient ],
                        message    : String) throws {
        guard let sender = sender else { // should never happen
            assertionFailure("got empty message sender!")
            return
        }
        delegate?.client(self, message: message, from: sender, for: recipients)
    }
    
    open func doNick(_ newNick: IRCNickName) throws {
        switch state {
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            state = .registering(channel: channel, nick: newNick, userInfo: info)
            
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            state = .registered(channel: channel, nick: newNick, userInfo: info)
            
        default: return // hmm
        }
        
        delegate?.client(self, changedNickTo: newNick)
    }
    
    open func doMode(nick: IRCNickName, add: IRCUserMode, remove: IRCUserMode) throws {
        guard let myNick = state.nick, myNick == nick else {
            return
        }
        
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            delegate?.client(self, changedUserModeTo: newMode)
        }
    }
    
    open func doPing(_ server: String, server2: String? = nil) throws {
        let msg : IRCMessage
        
        msg = IRCMessage(origin: origin, // probably wrong
                         command: .PONG(server: server, server2: server))
        sendMessage(msg)
    }
}
