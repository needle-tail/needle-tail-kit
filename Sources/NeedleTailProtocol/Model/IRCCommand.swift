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

    public var commandAsString : String {
        switch self {
        case .NICK:
            return Constants.nick
        case .USER:
            return Constants.user
        case .ISON:
            return Constants.isOn
        case .QUIT:
            return Constants.quit
        case .PING:
            return Constants.isOn
        case .PONG:
            return Constants.pong
        case .JOIN, .JOIN0:
            return Constants.join
        case .PART:
            return Constants.part
        case .LIST:
            return Constants.list
        case .PRIVMSG:
            return Constants.privMsg
        case .NOTICE:
            return Constants.notice
        case .CAP:
            return Constants.cap
        case .MODE, .MODEGET:
            return Constants.mode
        case .WHOIS:
            return Constants.whoIs
        case .WHO:
            return Constants.who
        case .CHANNELMODE:
            return Constants.mode
        case .CHANNELMODE_GET, .CHANNELMODE_GET_BANMASK:
            return Constants.mode

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
                return [ info.username, usermask.stringValue, Constants.star, info.realname ]
            }
            else {
                return [ info.username,
                         info.hostname ?? info.usermask?.stringValue ?? Constants.star,
                         info.servername ?? Constants.star,
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
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma) ]
        case .JOIN(let channels, .some(let keys)):
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma),
                     keys.joined(separator: Constants.comma)]

        case .JOIN0: return [ "0" ]

        case .PART(let channels):
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma) ]

        case .LIST(let channels, .none):
            guard let channels = channels else { return [] }
            return [ channels.map { $0.stringValue }.joined(separator: Constants.comma) ]
        case .LIST(let channels, .some(let target)):
            return [ (channels ?? []).map { $0.stringValue }.joined(separator: Constants.comma),
                     target ]

        case .PRIVMSG(let recipients, let m), .NOTICE (let recipients, let m):
            return [ recipients.map { $0.stringValue }.joined(separator: Constants.comma), m ]

        case .MODE(let name, let add, let remove):
            if add.isEmpty && remove.isEmpty { return [ name.stringValue, Constants.none ] }
            else if !add.isEmpty && !remove.isEmpty {
                return [ name.stringValue,
                         Constants.plus + add.stringValue, Constants.minus + remove.stringValue ]
            }
            else if !remove.isEmpty {
                return [ name.stringValue, Constants.minus + remove.stringValue ]
            }
            else {
                return [ name.stringValue, Constants.plus + add.stringValue ]
            }
        case .CHANNELMODE(let name, let add, let remove):
            if add.isEmpty && remove.isEmpty { return [ name.stringValue, Constants.none ] }
            else if !add.isEmpty && !remove.isEmpty {
                return [ name.stringValue,
                         Constants.plus + add.stringValue, Constants.minus + remove.stringValue ]
            }
            else if !remove.isEmpty {
                return [ name.stringValue, Constants.minus + remove.stringValue ]
            }
            else {
                return [ name.stringValue, Constants.plus + add.stringValue ]
            }
        case .MODEGET(let name):
            return [ name.stringValue ]
        case .CHANNELMODE_GET(let name), .CHANNELMODE_GET_BANMASK(let name):
            return [ name.stringValue ]
        case .WHOIS(.some(let server), let usermasks):
            return [ server, usermasks.joined(separator: Constants.comma)]
        case .WHOIS(.none, let usermasks):
            return [ usermasks.joined(separator: Constants.comma) ]
        case .WHO(.none, _):
            return []
        case .WHO(.some(let usermask), false):
            return [ usermask ]
        case .WHO(.some(let usermask), true):
            return [ usermask, Constants.oString ]

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
            return Constants.quit + Constants.space + "'\(v)'"
        case .QUIT(.none):
            return Constants.quit
        case .NICK(let v):
            return Constants.nick + Constants.space + "\(v)"
        case .USER(let v):
            return Constants.user + Constants.space + "\(v)"
        case .ISON(let v):
            let nicks = v.map { $0.stringValue}
            return Constants.isOn + Constants.space + nicks.joined(separator: Constants.comma)
        case .MODEGET(let nick):
            return Constants.mode + Constants.space + "\(nick)"
        case .MODE(let nick, let add, let remove):
            var s = Constants.mode + Constants.space + "\(nick)"
            if !add   .isEmpty { s += Constants.space + Constants.plus + add.stringValue }
            if !remove.isEmpty { s += Constants.space + Constants.minus + remove.stringValue }
            return s
        case .CHANNELMODE_GET(let v):
            return Constants.mode + Constants.space + "\(v)"
        case .CHANNELMODE_GET_BANMASK(let v):
            return Constants.mode + Constants.space + Constants.bString + Constants.space + "\(v)"
        case .CHANNELMODE(let nick, let add, let remove):
            var s = Constants.mode + Constants.space + "\(nick)"
            if !add   .isEmpty { s += Constants.space + Constants.plus + add.stringValue }
            if !remove.isEmpty { s += Constants.space + Constants.minus + remove.stringValue }
            return s
        case .JOIN0:
            return Constants.join0
        case .JOIN(let channels, .none):
            let names = channels.map { $0.stringValue}
            return Constants.join + Constants.space + names.joined(separator: Constants.comma)
        case .JOIN(let channels, .some(let keys)):
            let names = channels.map { $0.stringValue}
            return Constants.join + Constants.space + names.joined(separator: Constants.comma)
            + Constants.space + Constants.keys + Constants.space + keys.joined(separator: Constants.comma)
        case .PART(let channels):
            let names = channels.map { $0.stringValue}
            return Constants.part + names.joined(separator: Constants.comma)
        case .LIST(.none, .none):
            return Constants.list + Constants.space + Constants.star
        case .LIST(.none, .some(let target)):
            return Constants.list + Constants.space + Constants.star + Constants.space + Constants.atString + target
        case .LIST(.some(let channels), .none):
            let names = channels.map { $0.stringValue}
            return Constants.list + Constants.space + names.joined(separator: Constants.comma) + Constants.space
        case .LIST(.some(let channels), .some(let target)):
            let names = channels.map { $0.stringValue}
            return Constants.list + Constants.space + Constants.atString + target + names.joined(separator: Constants.comma) + Constants.space
        case .PRIVMSG(let recipients, let message):
            let to = recipients.map { $0.description }
            return Constants.privMsg + Constants.space + to.joined(separator: Constants.comma) + Constants.space + "'\(message)'"
        case .NOTICE (let recipients, let message):
            let to = recipients.map { $0.description }
            return Constants.notice + Constants.space + to.joined(separator: Constants.comma) + Constants.space + "'\(message)'"
        case .CAP(let subcmd, let capIDs):
            return Constants.cap + Constants.space + "\(subcmd)" + capIDs.joined(separator: Constants.comma)
        case .WHOIS(.none, let masks):
            return Constants.whoIs + Constants.space + masks.joined(separator: Constants.comma) + Constants.space
        case .WHOIS(.some(let target), let masks):
            return Constants.whoIs + Constants.space + Constants.atString + target + Constants.space + masks.joined(separator: Constants.comma) + Constants.space
        case .WHO(.none, _):
            return Constants.who
        case .WHO(.some(let mask), let opOnly):
            let opertorOnly = opOnly ? Constants.space + Constants.oString : Constants.none
            return Constants.who + Constants.space + mask + opertorOnly;
        case .otherCommand(let cmd, let args):
            return "<IRCCmd: \(cmd) args=\(args.joined(separator: Constants.comma))>"
        case .otherNumeric(let cmd, let args):
            return "<IRCCmd: \(cmd) args=\(args.joined(separator: Constants.comma))>"
        case .numeric(let cmd, let args):
            return "<IRCCmd: \(cmd.rawValue) args=\(args.joined(separator: Constants.comma))>"
        }
    }
}
