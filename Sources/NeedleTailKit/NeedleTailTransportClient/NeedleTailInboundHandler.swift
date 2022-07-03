//
//  NeedleTailInboundHandler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import Logging
import AsyncIRC
import NeedleTailHelpers

final class NeedleTailInboundHandler : ChannelInboundHandler {
    
    typealias InboundIn = IRCMessage
    
    let client: NeedleTailTransportClient
    let logger: Logger
    
    init(client: NeedleTailTransportClient) {
        self.logger = Logger(label: "NeedleTailInboundHandler")
        self.client = client
    }
    
    func channelActive(context: ChannelHandlerContext) {
        logger.info("Channel Active")
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        logger.info("Channel Inactive")
        Task {
            await client.handlerDidDisconnect(context)
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        Task {
            do {
            let message = unwrapInboundIn(data)
                try await client.processReceivedMessages(message)
            } catch let error as NeedleTailError {
                logger.error("\(error.rawValue)")
            }
        }
    }
    
    @NeedleTailTransportActor
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.client.handlerCaughtError(error, in: context)
        context.close(promise: nil)
    }
    
}
