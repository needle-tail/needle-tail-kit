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

import NIO
import Logging
import Foundation
import NeedleTailHelpers

public let DefaultIRCPort = 6667


/**
 * Protocol handler for IRC
 *
 * The IRC protocol is specified in RFC 2812, which updates RFC 1459. However,
 * servers don't usually adhere to the specs :->
 *
 * Samples:
 *
 *     NICK noze
 *     USER noze 0 * :Noze io
 *     :noze JOIN :#nozechannel
 *     :cherryh.freenode.net 366 helge99 #GNUstep :End of /NAMES list.
 *
 * Basic syntax:
 *
 *     [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?
 *
 */
public class IRCChannelHandler : ChannelDuplexHandler {
    
    //    public typealias InboundErr  = MessageParserError
    
    public typealias InboundIn   = ByteBuffer
    public typealias InboundOut  = IRCMessage
    
    public typealias OutboundIn  = IRCMessage
    public typealias OutboundOut = ByteBuffer
    var logger: Logger
    let consumer = ParseConsumer()
    
    public init(logger: Logger = Logger(label: "NeedleTailKit")) {
        self.logger = logger
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.logger.trace("IRCChannelHandler is Active")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.logger.trace("IRCChannelHandler is Inactive")
        context.fireChannelInactive()
    }
    
    
    // MARK: - Reading
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = self.unwrapInboundIn(data)
        let lines = buffer.readString(length: buffer.readableBytes) ?? ""
        self.logger.trace("IRCChannelHandler Read \(lines)")
        
        guard !lines.isEmpty else { return }
        let lineArray = lines.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
            .filter{ $0 != ""}
        
        _ = lineArray.compactMap { string in
            let message = asyncParse(context: context, line: string)
            message.whenComplete{ switch $0 {
            case .success(let message):
                self.channelRead(context: context, value: message)
            case .failure(let error):
                self.logger.error("AsyncParse Failed \(error)")
            }
            }
        }
    }
    
    private func asyncParse(context: ChannelHandlerContext, line: String) -> EventLoopFuture<IRCMessage> {
        let promise = context.eventLoop.makePromise(of: IRCMessage.self)
        promise.completeWithTask {
            guard let message = await self.processMessage(line) else {
                return try await promise.futureResult.get()
            }
            return message
        }
        return promise.futureResult
    }
    
    let parser = MessageParser()
    
    @NeedleTailKitActor
    public func processMessage(_ message: String) async -> IRCMessage? {
        await consumer.feedConsumer(message)
        
        do {
            func parseSequence() async -> ParseSequenceResult? {
                var sequence = ParserSequence(consumer: consumer).makeAsyncIterator()
                return try? await sequence.next()
            }
            
            switch await parseSequence() {
            case.success(let message):
                return try await IRCTaskHelpers.parseMessageTask(task: message, messageParser: parser)
            case .finished:
                return nil
            default:
                return nil
            }
        } catch {
            logger.error("Parser Sequence Error: \(error)")
        }
        return nil
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        self.logger.trace("READ Complete")
    }
    
    public func channelRead(context: ChannelHandlerContext, value: InboundOut) {
        context.fireChannelRead(self.wrapInboundOut(value))
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        context.fireErrorCaught(MessageParserError.transportError(error))
    }
    
    
    // MARK: - Writing
    
    public func write(context: ChannelHandlerContext, data: NIOAny,
                      promise: EventLoopPromise<Void>?
    ) {
        let message: OutboundIn = self.unwrapOutboundIn(data)
        write(context: context, value: message, promise: promise)
    }
    
    public final func write(context: ChannelHandlerContext, value: IRCMessage,
                            promise: EventLoopPromise<Void>?
    ) {
        var buffer = context.channel.allocator.buffer(capacity: 200)
        encode(value: value, target: value.target, into: &buffer)
        context.write(NIOAny(buffer), promise: promise)
    }
    
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

extension ByteBuffer {
    
    mutating func writeCSVArgument<T: Sequence>(_ args: T)
    where T.Element == String
    {
        let cSpace : UInt8 = 32
        let cComma : UInt8 = 44
        
        writeInteger(cSpace)
        
        var isFirst = true
        for arg in args {
            if isFirst { isFirst = false }
            else { writeInteger(cComma) }
            writeString(arg)
        }
    }
    
    mutating func writeArguments<T: Sequence>(_ args: T)
    where T.Element == String
    {
        let cSpace : UInt8 = 32
        
        for arg in args {
            writeInteger(cSpace)
            writeString(arg)
        }
    }
    
    mutating func writeArguments<T: Collection>(_ args: T, useLast: Bool = false)
    where T.Element == String
    {
        let cSpace : UInt8 = 32
        
        guard !args.isEmpty else { return }
        
        for arg in args.dropLast() {
            writeInteger(cSpace)
            writeString(arg)
        }
        
        let lastIdx = args.index(args.startIndex, offsetBy: args.count - 1)
        return writeLastArgument(args[lastIdx])
    }
    
    mutating func writeLastArgument(_ s: String) {
        let cSpace : UInt8 = 32
        let cColon : UInt8 = 58
        
        writeInteger(cSpace)
        writeInteger(cColon)
        writeString(s)
    }
}
