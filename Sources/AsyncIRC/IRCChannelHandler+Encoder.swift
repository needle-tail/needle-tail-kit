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

import NIOCore

extension IRCChannelHandler {
    func encode(value: IRCMessage, target: String?,
                into buffer: inout ByteBuffer
    ) {
        let cColon : UInt8 = 58
        let cSpace : UInt8 = 32
        let cStar  : UInt8 = 42
        let cCR    : UInt8 = 13
        let cLF    : UInt8 = 10
        
        if value.tags != [], value.tags != nil {
            for tag in value.tags ?? [] {
                buffer.writeString("@\(tag.key)=")
                buffer.writeString("\(tag.value);")
            }
            buffer.writeInteger(cSpace)
        }
        
        if let origin = value.origin, !origin.isEmpty {
            buffer.writeInteger(cColon)
            buffer.writeString(origin)
            buffer.writeInteger(cSpace)
        }
        
        buffer.writeString(value.command.commandAsString)
        
        if let s = target {
            buffer.writeInteger(cSpace)
            buffer.writeString(s)
        }
        
        switch value.command {
        case .PING(let s, let s2), .PONG(let s, let s2):
            if let s2 = s2 {
                buffer.writeInteger(cSpace)
                buffer.writeString(s)
                buffer.writeLastArgument(s2)
            }
            else {
                buffer.writeLastArgument(s)
            }
            
        case .QUIT(.some(let v)):
            buffer.writeLastArgument(v)
            
        case .NICK(let v), .MODEGET(let v):
            buffer.writeInteger(cSpace)
            buffer.writeString(v.stringValue)
            
        case .MODE(let nick, let add, let remove):
            buffer.writeInteger(cSpace)
            buffer.writeString(nick.stringValue)
            
            let adds = add   .stringValue.map { "+\($0)" }
            let rems = remove.stringValue.map { "-\($0)" }
            if adds.isEmpty && rems.isEmpty {
                buffer.writeLastArgument("")
            }
            else {
                buffer.writeArguments(adds + rems, useLast: true)
            }
            
        case .CHANNELMODE_GET(let v):
            buffer.writeInteger(cSpace)
            buffer.writeString(v.stringValue)
            
        case .CHANNELMODE_GET_BANMASK(let v):
            buffer.writeInteger(cSpace)
            buffer.writeInteger(UInt8(98)) // 'b'
            buffer.writeInteger(cSpace)
            buffer.writeString(v.stringValue)
            
        case .CHANNELMODE(let channel, let add, let remove):
            buffer.writeInteger(cSpace)
            buffer.writeString(channel.stringValue)
            
            let adds = add   .stringValue.map { "+\($0)" }
            let rems = remove.stringValue.map { "-\($0)" }
            buffer.writeArguments(adds + rems, useLast: true)
            
        case .USER(let userInfo):
            buffer.writeInteger(cSpace)
            buffer.writeString(userInfo.username)
            if let mask = userInfo.usermask {
                buffer.writeInteger(cSpace)
                buffer.write(integerAsString: Int(mask.maskValue))
                buffer.writeInteger(cSpace)
                buffer.writeInteger(cStar)
            }
            else {
                buffer.writeInteger(cSpace)
                buffer.writeString(userInfo.hostname ?? "*")
                buffer.writeInteger(cSpace)
                buffer.writeString(userInfo.servername ?? "*")
            }
            buffer.writeLastArgument(userInfo.realname)
            
        case .QUIT(.none):
            break
            
        case .ISON(let nicks):
            buffer.writeArguments(nicks.lazy.map { $0.stringValue })
            
        case .JOIN0:
            buffer.writeString(" *")
            
        case .JOIN(let channels, let keys):
            buffer.writeCSVArgument(channels.lazy.map { $0.stringValue })
            if let keys = keys { buffer.writeCSVArgument(keys) }
            
        case .PART(let channels, let message):
            buffer.writeCSVArgument(channels.lazy.map { $0.stringValue })
            if let message = message { buffer.writeLastArgument(message) }
            
        case .LIST(let channels, let target):
            if let channels = channels {
                buffer.writeCSVArgument(channels.lazy.map { $0.stringValue })
            }
            else { buffer.writeString(" *") }
            if let target = target { buffer.writeLastArgument(target) }
            
        case .PRIVMSG(let recipients, let message),
                .NOTICE (let recipients, let message):
            buffer.writeCSVArgument(recipients.lazy.map { $0.stringValue })
            buffer.writeLastArgument(message)

        case .CAP(let subcmd, let capIDs):
            buffer.writeInteger(cSpace)
            buffer.writeString(subcmd.commandAsString)
            buffer.writeLastArgument(capIDs.joined(separator: " "))
            
        case .WHOIS(let target, let masks):
            if let target = target {
                buffer.writeInteger(cSpace)
                buffer.writeString(target)
            }
            buffer.writeInteger(cSpace)
            buffer.writeString(masks.joined(separator: ","))
            
        case .WHO(let mask, let opOnly):
            if let mask = mask {
                buffer.writeInteger(cSpace)
                buffer.writeString(mask)
                if opOnly {
                    buffer.writeInteger(cSpace)
                    buffer.writeInteger(UInt8(111)) // o
                }
            }
            
        case .otherCommand(_, let args),
                .otherNumeric(_, let args),
                .numeric     (_, let args):
            buffer.writeArguments(args, useLast: true)
        }
        
        buffer.writeInteger(cCR)
        buffer.writeInteger(cLF)
    }
}
