//
//  IRCClient+IRCDispatcher.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO


@globalActor public final actor InboundActor {
    public static let shared = InboundActor()
    private init() {}
}

@globalActor public final actor OutboundActor {
    public static let shared = OutboundActor()
    private init() {}
}


extension IRCClient: IRCDispatcher {
    
    public func irc_msgSend(_ message: IRCMessage) async throws {
        
        do {
            return try await irc_defaultMsgSend(message)
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
                await delegate?.client(self, messageOfTheDay: messageOfTheDay)
            }
            messageOfTheDay = ""
        case .numeric(.replyNameReply, _ /*let args*/):
            break
        case .numeric(.replyEndOfNames, _):
            break
        case .numeric(.replyInfo, let info):
            try await delegate?.client(self, info: info)
        case .numeric(.replyKeyBundle, let bundle):
            try await delegate?.client(self, keyBundle: bundle)
        case .numeric(.replyTopic, let args):
            // :localhost 332 Guest31 #NIO :Welcome to #nio!
            guard args.count > 2, let channel = IRCChannelName(args[3]) else {
                return print("ERROR: topic args incomplete:", message)
            }
            await delegate?.client(self, changeTopic: args[2], of: channel)
            
            /* join/part, we need the origin here ... (fix dispatcher) */
            
        case .JOIN(let channels, _):
            guard let origin = message.origin, let user = IRCUserID(origin) else {
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            await delegate?.client(self, user: user, joined: channels)
            
        case .PART(let channels, let leaveMessage):
            guard let origin = message.origin, let user = IRCUserID(origin) else {
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            await delegate?.client(self, user: user, left: channels, with: leaveMessage)
        case .otherNumeric(let code, let args):
            logger.trace("otherNumeric Code: - \(code)")
            logger.trace("otherNumeric Args: - \(args)")
            await delegate?.client(self, received: message)
        case .QUIT(let message):
            await delegate?.client(self, quit: message)
        default:
            await delegate?.client(self, received: message)
        }
    }
    
    
    public func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws {
        await delegate?.client(self, notice: message, for: recipients)
    }
    
    
    public func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?,
        userStatus: UserStatus
    ) async throws {
        guard let sender = sender else { // should never happen
            assertionFailure("got empty message sender!")
            return
        }
        await delegate?.client(self, message: message, from: sender, for: recipients)
    }
    
    public func doNick(_ newNick: IRCNickName) async throws {
        switch state {
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            state = .registering(channel: channel, nick: newNick, userInfo: info)
            
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            state = .registered(channel: channel, nick: newNick, userInfo: info)
            
        default: return // hmm
        }
        
        await delegate?.client(self, changedNickTo: newNick)
    }
    
    
    public func doMode(nick: IRCNickName, add: IRCUserMode, remove: IRCUserMode) async throws {
        guard let myNick = state.nick, myNick == nick else {
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
        await sendMessage(msg, chatDoc: nil)
    }
}
