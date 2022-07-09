//
//  NeedleTailInboundHandler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
@preconcurrency import Logging
import AsyncIRC
import NeedleTailHelpers
import NIOConcurrencyHelpers


final class NeedleTailInboundHandler: ChannelInboundHandler, Sendable {
    
    typealias InboundIn = IRCMessage
    
    let client: NeedleTailTransportClient
    let logger = Logger(label: "NeedleTailInboundHandler")
    let lock = Lock()
    
    init(client: NeedleTailTransportClient) {
            lock.lock()
            self.client = client
            lock.unlock()
    }
    
    func channelActive(context: ChannelHandlerContext) {
        lock.withSendableLock {
            logger.info("Channel Active")
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        Task {
            lock.withSendableLock {
                logger.info("Channel Inactive")
            }
            await client.handlerDidDisconnect(context)
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        Task {
            try await lock.withSendableAsyncLock {
                do {
                    try await client.processReceivedMessages(message)
                } catch let error as NeedleTailError {
                    logger.error("\(error.rawValue)")
                }
            }
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        Task {
            await lock.withSendableAsyncLock {
                await self.client.handlerCaughtError(error, in: context)
                context.close(promise: nil)
            }
        }
    }
}
