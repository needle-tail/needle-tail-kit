//
//  IRCClient+IRCDispatcher.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import NeedleTailHelpers

extension IRCClient: IRCDispatcher {
    
    /// This is the client side message command processor. We decide what to do with each IRCMessage here
    /// - Parameter message: Our IRCMessage
    @NeedleTailActor
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
}
