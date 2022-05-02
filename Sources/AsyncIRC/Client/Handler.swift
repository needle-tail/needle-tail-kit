//
//  Handler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import Logging


// MARK: - Handler

final class Handler : ChannelInboundHandler {
    
    typealias InboundIn = IRCMessage
    
    let client: IRCClient
    let logger: Logger
    
    init(client: IRCClient) {
        self.logger = Logger(label: "Handler: ")
        self.client = client
    }
    
    func channelActive(context: ChannelHandlerContext) {
        logger.info("Client Handler Active")
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        Task {
            await client.handlerDidDisconnect(context)
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        Task {
            do {
            let message = unwrapInboundIn(data)
                try await client.processReceivedMessages(message)
            } catch {
                logger.error("handle dispatcher error: \(error)")
            }
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.client.handlerCaughtError(error, in: context)
        context.close(promise: nil)
    }
    
}
