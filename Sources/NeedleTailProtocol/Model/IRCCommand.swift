//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2021 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import NeedleTailHelpers

public enum IRCCommand: Codable, Sendable {
    
    case NICK(NeedleTailNick)
    case USER(IRCUserInfo)
    case ISON([NeedleTailNick])
    case QUIT(String?)
    case PING(server: String, server2: String?)
    case PONG(server: String, server2: String?)
    /// Keys are passwords for a Channel.
    case JOIN(channels: [ IRCChannelName ], keys: [ String ]?)
    /// JOIN-0 is actually "unsubscribe all channels"
    case JOIN0
    /// Unsubscribe the given channels.
    case PART(channels: [ IRCChannelName ])
    case LIST(channels: [ IRCChannelName ]?, target: String?)
    case PRIVMSG([ IRCMessageRecipient ], String)
    case NOTICE ([ IRCMessageRecipient ], String)
    case MODE(NeedleTailNick, add: IRCUserMode, remove: IRCUserMode)
    case MODEGET(NeedleTailNick)
    case CHANNELMODE(IRCChannelName, add: IRCChannelMode, remove: IRCChannelMode)
    case CHANNELMODE_GET(IRCChannelName)
    case CHANNELMODE_GET_BANMASK(IRCChannelName)
    case WHOIS(server: String?, usermasks: [ String ])
    case WHO(usermask: String?, onlyOperators: Bool)
    case KICK([IRCChannelName], [NeedleTailNick], [String])
    case KILL(NeedleTailNick, String)
    
    case numeric(IRCCommandCode, [ String ])
    case otherCommand(String, [ String ])
    case otherNumeric(Int, [ String ])
    
    
    // MARK: - IRCv3.net
    
    public enum CAPSubCommand: String, Sendable, Codable {
        case LS, LIST, REQ, ACK, NAK, END
        public var commandAsString : String { return rawValue }
    }
    case CAP(CAPSubCommand, [ String ])
}


// MARK: - Description

extension IRCCommand: CustomStringConvertible {
    
    public var commandAsString: String {
        switch self {
        case .NICK:
            return Constants.nick.rawValue
        case .USER:
            return Constants.user.rawValue
        case .ISON:
            return Constants.isOn.rawValue
        case .QUIT:
            return Constants.quit.rawValue
        case .PING:
            return Constants.ping.rawValue
        case .PONG:
            return Constants.pong.rawValue
        case .JOIN:
            return Constants.join.rawValue
        case.JOIN0:
            return Constants.join0.rawValue
        case .PART:
            return Constants.part.rawValue
        case .LIST:
            return Constants.list.rawValue
        case .PRIVMSG:
            return Constants.privMsg.rawValue
        case .NOTICE:
            return Constants.notice.rawValue
        case .CAP:
            return Constants.cap.rawValue
        case .MODE, .MODEGET:
            return Constants.mode.rawValue
        case .WHOIS:
            return Constants.whoIs.rawValue
        case .WHO:
            return Constants.who.rawValue
        case .CHANNELMODE:
            return Constants.mode.rawValue
        case .CHANNELMODE_GET, .CHANNELMODE_GET_BANMASK:
            return Constants.mode.rawValue
        case .KICK:
            return Constants.kick.rawValue
        case .KILL:
            return Constants.kill.rawValue
        case .otherCommand(let cmd, _):
            return cmd
        case .otherNumeric(let cmd, _):
            let s = String(cmd)
            if s.count >= 3 { return s }
            return String(repeating: "0", count: 3 - s.count) + s
        case .numeric(let cmd, _):
            let s = String(cmd.rawValue)
            if s.count >= 3 { return s }
            return String(repeating: "0", count: 3 - s.count) + s
        }
    }
    
    public var arguments : [ String ] {
        switch self {
        case .NICK(let nick):
            return [ nick.stringValue ]
        case .USER(let info):
            if let usermask = info.usermask {
                return [ info.username, usermask.stringValue, Constants.star.rawValue, info.realname ]
            } else {
                return [ info.username,
                         info.hostname ?? info.usermask?.stringValue ?? Constants.star.rawValue,
                         info.servername ?? Constants.star.rawValue,
                         info.realname ]
            }
            
        case .ISON(let nicks): return nicks.map { $0.stringValue }
            
        case .QUIT(.none):                          return []
        case .QUIT(.some(let message)):             return [ message ]
        case .PING(let server, .none):              return [ server ]
        case .PONG(let server, .none):              return [ server ]
        case .PING(let server, .some(let server2)): return [ server, server2 ]
        case .PONG(let server, .some(let server2)): return [ server, server2 ]
            
        case .JOIN(let channels, .none):
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma.rawValue) ]
        case .JOIN(let channels, .some(let keys)):
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma.rawValue),
                     keys.joined(separator: Constants.comma.rawValue)]
            
        case .JOIN0: return [ "0" ]
            
        case .PART(let channels):
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma.rawValue) ]
            
        case .LIST(let channels, .none):
            guard let channels = channels else { return [] }
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma.rawValue) ]
        case .LIST(let channels, .some(let target)):
            return [ (channels ?? []).map { $0.stringValue }.joined(separator: Constants.comma.rawValue),
                     target ]
            
        case .PRIVMSG(let recipients, let m), .NOTICE (let recipients, let m):
            return [ recipients.map { $0.stringValue }.joined(separator: Constants.comma.rawValue), m ]
            
        case .MODE(let name, let add, let remove):
            if add.isEmpty && remove.isEmpty { return [ name.stringValue, Constants.none.rawValue ] }
            else if !add.isEmpty && !remove.isEmpty {
                return [ name.stringValue,
                         Constants.plus.rawValue + add.stringValue, Constants.minus.rawValue + remove.stringValue ]
            }
            else if !remove.isEmpty {
                return [ name.stringValue, Constants.minus.rawValue + remove.stringValue ]
            }
            else {
                return [ name.stringValue, Constants.plus.rawValue + add.stringValue ]
            }
        case .CHANNELMODE(let name, let add, let remove):
            if add.isEmpty && remove.isEmpty { return [ name.stringValue, Constants.none.rawValue ] }
            else if !add.isEmpty && !remove.isEmpty {
                return [ name.stringValue,
                         Constants.plus.rawValue + add.stringValue, Constants.minus.rawValue + remove.stringValue ]
            }
            else if !remove.isEmpty {
                return [ name.stringValue, Constants.minus.rawValue + remove.stringValue ]
            }
            else {
                return [ name.stringValue, Constants.plus.rawValue + add.stringValue ]
            }
        case .MODEGET(let name):
            return [ name.stringValue ]
        case .CHANNELMODE_GET(let name), .CHANNELMODE_GET_BANMASK(let name):
            return [ name.stringValue ]
        case .WHOIS(.some(let server), let usermasks):
            return [ server, usermasks.joined(separator: Constants.comma.rawValue)]
        case .WHOIS(.none, let usermasks):
            return [ usermasks.joined(separator: Constants.comma.rawValue) ]
        case .WHO(.none, _):
            return []
        case .WHO(.some(let usermask), false):
            return [ usermask ]
        case .WHO(.some(let usermask), true):
            return [ usermask, Constants.oString.rawValue ]
        case .KICK(let channelNames, let users, let comments):
            if channelNames.count == users.count {
                return [
                    channelNames.map { $0.stringValue }.joined(separator: Constants.comma.rawValue),
                    users.map { $0.stringValue }.joined(separator: Constants.comma.rawValue),
                    comments.map { $0 }.joined(separator: Constants.comma.rawValue)
                ]
            } else {
                guard let firstChannel = channelNames.first else { return [] }
                guard let firstUser = users.first else { return [] }
                return [
                    firstChannel.stringValue,
                    firstUser.stringValue,
                    comments.map { $0 }.joined(separator: Constants.comma.rawValue)
                ]
            }
        case .KILL(let nick, let comment):
            return [nick.stringValue, comment]
        case .numeric     (_, let args),
                .otherCommand(_, let args),
                .otherNumeric(_, let args):
            return args
            
        default: // TBD: which case do we miss???
            fatalError("unexpected case \(self)")
        }
    }
    
    public var description : String {
        switch self {
        case .PING(let server, let server2), .PONG(let server, let server2):
            if let server2 = server2 {
                return "\(commandAsString) '\(server)' '\(server2)'"
            }
            else {
                return "\(commandAsString) '\(server)'"
            }
        case .QUIT(.some(let v)):
            return Constants.quit.rawValue + Constants.space.rawValue + "'\(v)'"
        case .QUIT(.none):
            return Constants.quit.rawValue
        case .NICK(let v):
            return Constants.nick.rawValue + Constants.space.rawValue + "\(v)"
        case .USER(let v):
            return Constants.user.rawValue + Constants.space.rawValue + "\(v)"
        case .ISON(let v):
            let nicks = v.map { $0.stringValue}
            return Constants.isOn.rawValue + Constants.space.rawValue + nicks.joined(separator: Constants.comma.rawValue)
        case .MODEGET(let nick):
            return Constants.mode.rawValue + Constants.space.rawValue + "\(nick)"
        case .MODE(let nick, let add, let remove):
            var s = Constants.mode.rawValue + Constants.space.rawValue + "\(nick)"
            if !add   .isEmpty { s += Constants.space.rawValue + Constants.plus.rawValue + add.stringValue }
            if !remove.isEmpty { s += Constants.space.rawValue + Constants.minus.rawValue + remove.stringValue }
            return s
        case .CHANNELMODE_GET(let v):
            return Constants.mode.rawValue + Constants.space.rawValue + "\(v)"
        case .CHANNELMODE_GET_BANMASK(let v):
            return Constants.mode.rawValue + Constants.space.rawValue + "\(v)" + Constants.space.rawValue + Constants.plus.rawValue + Constants.bString.rawValue
        case .CHANNELMODE(let nick, let add, let remove):
            var s = Constants.mode.rawValue + Constants.space.rawValue + "\(nick)"
            if !add   .isEmpty { s += Constants.space.rawValue + Constants.plus.rawValue + add.stringValue }
            if !remove.isEmpty { s += Constants.space.rawValue + Constants.minus.rawValue + remove.stringValue }
            return s
        case .JOIN0:
            return Constants.join0.rawValue
        case .JOIN(let channels, .none):
            let names = channels.map { $0.stringValue}
            return Constants.join.rawValue + Constants.space.rawValue + names.joined(separator: Constants.comma.rawValue)
        case .JOIN(let channels, .some(let keys)):
            let names = channels.map { $0.stringValue}
            return Constants.join.rawValue + Constants.space.rawValue + names.joined(separator: Constants.comma.rawValue)
            + Constants.space.rawValue + Constants.keys.rawValue + Constants.space.rawValue + keys.joined(separator: Constants.comma.rawValue)
        case .PART(let channels):
            let names = channels.map { $0.stringValue}
            return Constants.part.rawValue + Constants.space.rawValue + names.joined(separator: Constants.comma.rawValue +  Constants.space.rawValue)
        case .LIST(.none, .none):
            return Constants.list.rawValue + Constants.space.rawValue + Constants.star.rawValue
        case .LIST(.none, .some(let target)):
            return Constants.list.rawValue + Constants.space.rawValue + Constants.star.rawValue + Constants.space.rawValue + Constants.atString.rawValue + target
        case .LIST(.some(let channels), .none):
            let names = channels.map { $0.stringValue}
            return Constants.list.rawValue + Constants.space.rawValue + names.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue
        case .LIST(.some(let channels), .some(let target)):
            let names = channels.map { $0.stringValue}
            return Constants.list.rawValue + Constants.space.rawValue + Constants.atString.rawValue + target + names.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue
        case .PRIVMSG(let recipients, let message):
            let to = recipients.map { $0.description }
            return Constants.privMsg.rawValue + Constants.space.rawValue + to.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue + "'\(message)'"
        case .NOTICE (let recipients, let message):
            let to = recipients.map { $0.description }
            return Constants.notice.rawValue + Constants.space.rawValue + to.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue + "'\(message)'"
        case .CAP(let subcmd, let capIDs):
            return Constants.cap.rawValue + Constants.space.rawValue + "\(subcmd)" + capIDs.joined(separator: Constants.comma.rawValue)
        case .WHOIS(.none, let masks):
            return Constants.whoIs.rawValue + Constants.space.rawValue + masks.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue
        case .WHOIS(.some(let target), let masks):
            return Constants.whoIs.rawValue + Constants.space.rawValue + Constants.atString.rawValue + target + Constants.space.rawValue + masks.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue
        case .WHO(.none, _):
            return Constants.who.rawValue
        case .WHO(.some(let mask), let opOnly):
            let opertorOnly = opOnly ? Constants.space.rawValue + Constants.oString.rawValue : Constants.none.rawValue
            return Constants.who.rawValue + Constants.space.rawValue + mask + opertorOnly;
        case .KICK(let channels, let users, let comments):
            let channels = channels.map { $0.stringValue}
            let users = users.map { $0.stringValue}
            let comments = comments.map { $0}
            return Constants.kick.rawValue + Constants.space.rawValue + channels.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue + users.joined(separator: Constants.comma.rawValue) + Constants.space.rawValue + comments.joined(separator: Constants.comma.rawValue)
        case .KILL(let nick, let comment):
            return Constants.kill.rawValue + Constants.space.rawValue + "\(nick)" + Constants.space.rawValue + "\(comment)"
        case .otherCommand(let cmd, let args):
            return "<IRCCmd: \(cmd) args=\(args.joined(separator: Constants.comma.rawValue))>"
        case .otherNumeric(let cmd, let args):
            return "<IRCCmd: \(cmd) args=\(args.joined(separator: Constants.comma.rawValue))>"
        case .numeric(let cmd, let args):
            return "<IRCCmd: \(cmd.rawValue) args=\(args.joined(separator: Constants.comma.rawValue))>"
        }
    }
}
