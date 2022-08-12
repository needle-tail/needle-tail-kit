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
    let logger = Logger(label: "NeedleTailHandler")
    
    init(client: NeedleTailClient, transport: NeedleTailTransport) {
        self.client = client
        self.transport = transport
    }
    
    func channelActive(context: ChannelHandlerContext) {
        logger.info("Channel Active")
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        let task = Task {
            logger.info("Channel Inactive")
        }
        task.cancel()
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let task = Task {
            let message = unwrapInboundIn(data)
            do {
                try await transport.processReceivedMessages(message)
            } catch let error as NeedleTailError {
                logger.error("\(error.rawValue)")
            } catch {
                logger.error("\(error)")
            }
        }
        task.cancel()
    }
    
    @NeedleTailClientActor
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print(error)
        context.close(promise: nil)
    }
}
