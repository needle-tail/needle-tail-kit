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

import CypherProtocol
import NeedleTailHelpers

public extension IRCCommand {
    
    /**
     * This initializer creates `IRCCommand` values from String command names and
     * string arguments (as parsed by the `IRCMessageParser`).
     *
     * The parser validates the argument counts etc and throws exceptions on
     * unexpected input.
     */
    init(_ command: String, arguments: [ String ]) throws {
        typealias Error = MessageParserError
        
        func expect(argc: Int) throws {
            guard argc == arguments.count else {
                throw Error.invalidArgumentCount(command: command,
                                                 count: arguments.count, expected: argc)
            }
        }
        func expect(min: Int? = nil, max: Int? = nil) throws {
            if let max = max {
                guard arguments.count <= max else {
                    throw Error.invalidArgumentCount(command: command,
                                                     count: arguments.count,
                                                     expected: max)
                }
            }
            if let min = min {
                guard arguments.count >= min else {
                    throw Error.invalidArgumentCount(command: command,
                                                     count: arguments.count,
                                                     expected: min)
                }
            }
        }
        
        func splitChannelsString() throws -> [ IRCChannelName ] {
            var arguments = arguments
            return try arguments.removeFirst()
                .components(separatedBy: Constants.comma.rawValue)
                .compactMap { channel in
                    guard let first = channel.first else { throw Error.invalidChannelName(channel) }
                    guard let channel = IRCChannelName(first.isWhitespace ? String(channel.dropFirst()) : channel) else {
                        throw Error.invalidChannelName(channel)
                    }
                    return channel
                }
        }

        func splitRecipientString() throws -> [ IRCMessageRecipient ] {
            guard let firstArgument = arguments.first else {  throw Error.invalidMessageTarget(arguments.first ?? "") }
            return try firstArgument
                .split(separator: Character(Constants.comma.rawValue)).map {
                    guard let n = IRCMessageRecipient(String($0.trimmingCharacters(in: .whitespacesAndNewlines))) else {
                throw Error.invalidMessageTarget(String($0))
              }
                return n
            }
          }
        
        func splitNicks() throws -> [NeedleTailNick] {
            var nicks = [NeedleTailNick]()
            var arguments = arguments.dropLast()
            _ = try arguments.removeLast()
                .components(separatedBy: Constants.comma.rawValue)
                .compactMap({ name in
                    let seperated = String(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        .components(separatedBy: Constants.underScore.rawValue)
                    guard let name = seperated.first else { return }
                    guard let deviceId = seperated.last else { return }
                    guard let nick = NeedleTailNick(name: name, deviceId: DeviceId(deviceId)) else { throw NeedleTailError.nilNickName }
                    nicks.append(nick)
                })
            return nicks
        }
        
        func splitComments() -> [String] {
            var comments = [String]()
            _ = arguments[2].split(separator: Character(Constants.comma.rawValue)).map {
                comments.append(String($0))
            }
            return comments
        }
        
        switch command.uppercased() {
        case Constants.quit.rawValue:
            try expect(max: 1); self = .QUIT(arguments.first)
        case Constants.ping.rawValue:
            try expect(min: 1, max: 2)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let last = arguments.last else { throw Error.firstArgumentIsMissing }
            self = .PING(server: first,
                         server2: arguments.count > 1 ? last : nil)
        case Constants.pong.rawValue:
            try expect(min: 1, max: 2)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let last = arguments.last else { throw Error.firstArgumentIsMissing }
            self = .PONG(server: first,
                         server2: arguments.count > 1 ? last : nil)
            
        case Constants.nick.rawValue:
            try expect(argc: 1)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            let splitNick = first.components(separatedBy: Constants.underScore.rawValue)
            guard let name = splitNick.first else { throw Error.firstArgumentIsMissing }
            guard let id = splitNick.last else { throw Error.firstArgumentIsMissing }
                let deviceId = DeviceId(id)
                guard let nick = NeedleTailNick(name: name, deviceId: deviceId) else {
                    throw Error.invalidNickName(first)
                }
                self = .NICK(nick)
        case Constants.mode.rawValue:
            try expect(min: 1)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let recipient = IRCMessageRecipient(first) else {
                throw Error.invalidMessageTarget(first)
            }
            
            switch recipient {
            case .everything:
                guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
                throw Error.invalidMessageTarget(first)
                
            case .nick(let nick):
                if arguments.count > 1 {
                    var add = IRCUserMode()
                    var remove = IRCUserMode()
                    for arg in arguments.dropFirst() {
                        var isAdd = true
                        for c in arg {
                            if c == Character(Constants.plus.rawValue) {
                                isAdd = true
                            } else if c == Character(Constants.minus.rawValue) {
                                isAdd = false
                            } else if let mode = IRCUserMode(String(c)) {
                                if isAdd {
                                    add.insert(mode)
                                } else {
                                    remove.insert(mode)
                                }
                            } else {
                                // else: warn? throw?
                                print("IRCParser: unexpected IRC mode: \(c) \(arg)")
                            }
                        }
                    }
                    self = .MODE(nick, add: add, remove: remove)
                } else {
                    self = .MODEGET(nick)
                }
                
            case .channel(let channelName):
                if arguments.count > 1 {
                    var add = IRCChannelMode()
                    var remove = IRCChannelMode()
                    for arg in arguments.dropFirst() {
                        var isAdd = true
                        for c in arg {
                            if c == Character(Constants.plus.rawValue) {
                                isAdd = true
                            } else if c == Character(Constants.minus.rawValue) {
                                isAdd = false
                            } else if let mode = IRCChannelMode(String(c)) {
                                if isAdd {
                                    add.insert(mode)
                                } else {
                                    remove.insert(mode)
                                }
                            } else {
                                // else: warn? throw?
                                print("IRCParser: unexpected IRC mode: \(c) \(arg)")
                            }
                        }
                    }
                    if add == IRCChannelMode.banMask && remove.isEmpty {
                        self = .CHANNELMODE_GET_BANMASK(channelName)
                    } else {
                        self = .CHANNELMODE(channelName, add: add, remove: remove)
                    }
                }
                else {
                    self = .CHANNELMODE_GET(channelName)
                }
            }
            
        case Constants.user.rawValue:
            // RFC 1459 <username> <hostname> <servername> <realname>
            // RFC 2812 <username> <mode>     <unused>     <realname>
            try expect(argc: 4)
            if let mask = UInt16(arguments[1]) {
                self = .USER(IRCUserInfo(username : arguments[0],
                                         usermask : IRCUserMode(rawValue: mask),
                                         realname : arguments[3]))
            }
            else {
                self = .USER(IRCUserInfo(username   : arguments[0],
                                         hostname   : arguments[1],
                                         servername : arguments[2],
                                         realname   : arguments[3]))
            }
            
            
        case Constants.join.rawValue:
            try expect(min: 1, max: 2)
            if arguments.first == "0" {
                self = .JOIN0
            } else {
                let channels = try splitChannelsString()
                let keys = arguments.count > 1
                ? arguments.last?.split(separator: Character(Constants.comma.rawValue)).map(String.init)
                : nil
                self = .JOIN(channels: channels, keys: keys)
            }
            
        case Constants.part.rawValue:
            try expect(min: 1, max: 2)
            let channels = try splitChannelsString()
            self = .PART(channels: channels)
            
        case Constants.list.rawValue:
            try expect(max: 2)
            
            let channels = arguments.count > 0
            ? try splitChannelsString() : nil
            let target   = arguments.count > 1 ? arguments.first : nil
            self = .LIST(channels: channels, target: target)
            
        case Constants.isOn.rawValue:
            try expect(min: 1)
            var nicks = [NeedleTailNick]()
            for arg in arguments {
                let splitNick = arg.split(separator: Character(Constants.underScore.rawValue))
                guard let nick = splitNick.first else { throw Error.invalidNickName(arg) }
                guard let deviceId = splitNick.last else { throw Error.invalidNickName(arg) }
                guard let nick = NeedleTailNick(name: String(nick), deviceId: DeviceId(String(deviceId))) else {
                    throw Error.invalidNickName(arg)
                }
                
                nicks.append(nick)
            }
            self = .ISON(nicks)
            
        case Constants.privMsg.rawValue:
            try expect(argc: 2)
            let targets = try splitRecipientString()
            guard let last = arguments.last else { throw Error.lastArgumentIsMissing }
            self = .PRIVMSG(targets, last)
            
        case Constants.notice.rawValue:
            try expect(argc: 2)
            let targets = try splitRecipientString()
            guard let last = arguments.last else { throw Error.lastArgumentIsMissing }
            self = .NOTICE(targets, last)
            
        case Constants.cap.rawValue:
            try expect(min: 1, max: 2)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let last = arguments.last else { throw Error.lastArgumentIsMissing }
            guard let subcmd = CAPSubCommand(rawValue: first) else {
                throw MessageParserError.invalidCAPCommand(first)
            }
            let capIDs = arguments.count > 1
            ? last.components(separatedBy: Constants.space.rawValue)
            : []
            self = .CAP(subcmd, capIDs)
            
        case Constants.whoIs.rawValue:
            try expect(min: 1, max: 2)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let last = arguments.last else { throw Error.lastArgumentIsMissing }
            let maskArg = arguments.count == 1 ? first : last
            let masks   = maskArg.split(separator: Character(Constants.comma.rawValue)).map(String.init)
            self = .WHOIS(server: arguments.count == 1 ? nil : first,
                          usermasks: Array(masks))
            
        case Constants.who.rawValue:
            try expect(max: 2)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let last = arguments.last else { throw Error.lastArgumentIsMissing }
            switch arguments.count {
            case 0: self = .WHO(usermask: nil, onlyOperators: false)
            case 1: self = .WHO(usermask: first, onlyOperators: false)
            case 2: self = .WHO(usermask: first,
                                onlyOperators: last == Constants.oString.rawValue)
            default: fatalError("unexpected argument count \(arguments.count)")
            }
            //Other Command, can be something like PASS, KEYBUNDLE
        case Constants.kill.rawValue:
            try expect(argc: 2)
            guard let first = arguments.first else { throw Error.firstArgumentIsMissing }
            guard let last = arguments.last else { throw Error.lastArgumentIsMissing }
            guard let nick = try splitNicks().first else { throw Error.invalidNickName(first) }
            self = .KILL(nick, last)
        case Constants.kick.rawValue:
            try expect(argc: 3)
            let channels = try splitChannelsString()
            let users = try splitNicks()
            let comments = splitComments()
            self = .KICK(channels, users, comments)
        default:
            self = .otherCommand(command.uppercased(), arguments)
        }
    }
    
    /**
     * This initializer creates `IRCCommand` values from numeric commands and
     * string arguments (as parsed by the `IRCMessageParser`).
     *
     * The parser validates the argument counts etc and throws exceptions on
     * unexpected input.
     */
    init(_ v: Int, arguments: [ String ]) throws {
        if let code = IRCCommandCode(rawValue: v) {
            self = .numeric(code, arguments)
        }
        else {
            self = .otherNumeric(v, arguments)
        }
    }
    
    /**
     * This initializer creates `IRCCommand` values from String command names and
     * string arguments (as parsed by the `IRCMessageParser`).
     *
     * The parser validates the argument counts etc and throws exceptions on
     * unexpected input.
     */
    init(_ s: String, _ arguments: String...) throws {
        try self.init(s, arguments: arguments)
    }
    
    /**
     * This initializer creates `IRCCommand` values from numeric commands and
     * string arguments (as parsed by the `IRCMessageParser`).
     *
     * The parser validates the argument counts etc and throws exceptions on
     * unexpected input.
     */
    init(_ v: Int, _ arguments: String...) throws {
        try self.init(v, arguments: arguments)
    }
}
