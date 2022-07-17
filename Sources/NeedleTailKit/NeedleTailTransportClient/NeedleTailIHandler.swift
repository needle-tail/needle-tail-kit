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


final class NeedleTailHandler: ChannelInboundHandler, Sendable {
    
    typealias InboundIn = IRCMessage
    
    let client: NeedleTailClient
    let transport: NeedleTailTransport
    let logger = Logger(label: "NeedleTailHandler")
    let lock = Lock()
    
    init(client: NeedleTailClient, transport: NeedleTailTransport) {
        lock.lock()
        self.client = client
        self.transport = transport
        lock.unlock()
    }
    
    func channelActive(context: ChannelHandlerContext) {
        lock.withSendableLock {
            logger.info("Channel Active")
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        _ = lock.withSendableLock {
        Task {
                logger.info("Channel Inactive")
                await self.client.handlerDidDisconnect(context)
            }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        _ = lock.withSendableLock {
        Task {
                let message = unwrapInboundIn(data)
                do {
                    try await transport.processReceivedMessages(message)
                } catch let error as NeedleTailError {
                    logger.error("\(error.rawValue)")
                } catch {
                    logger.error("\(error)")
                }
            }
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        _ = lock.withSendableLock {
        Task {
                await self.client.handlerCaughtError(error, in: context)
                context.close(promise: nil)
            }
        }
    }
}
