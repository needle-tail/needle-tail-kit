//
//  NeedleTailInboundHandler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import Logging
import NeedleTailProtocol
import NeedleTailHelpers
import NIOConcurrencyHelpers


final class NeedleTailHandler: ChannelInboundHandler {
    
    typealias InboundIn = IRCMessage
    
    let client: NeedleTailClient
    let transport: NeedleTailTransport
    var logger = Logger(label: "NeedleTailHandler")
    
    private var channel: Channel?
//    private var stream: NIOInboundChannelStream<InboundIn>?
    
    init(client: NeedleTailClient, transport: NeedleTailTransport) {
        self.client = client
        self.transport = transport
        self.logger.logLevel = .trace
    }
    
    func channelActive(context: ChannelHandlerContext) {
        logger.trace("Channel Active")
        self.channel = context.channel
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        logger.trace("Channel Inactive")
//        stream = nil
//        channel = nil
        context.fireChannelInactive()
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        _ = context.eventLoop.executeAsync {
            let message = self.unwrapInboundIn(data)
            do {
                try await self.transport.processReceivedMessages(message)
            } catch let error as NeedleTailError {
                self.logger.error("\(error.rawValue)")
            } catch {
                self.logger.error("\(error)")
            }
        }
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
