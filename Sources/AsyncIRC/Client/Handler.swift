//
//  Handler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO


// MARK: - Handler

final class Handler : ChannelInboundHandler {
    
    typealias InboundIn = IRCMessage
    
    let client : IRCClient
    
    init(client: IRCClient) {
        self.client = client
    }
    
    func channelActive(context: ChannelHandlerContext) {
        print("Client Handler Active")
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        Task {
            await client.handlerDidDisconnect(context)
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        Task {
            let value = unwrapInboundIn(data)
            await client.processReceivedMessages(value)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.client.handlerCaughtError(error, in: context)
        context.close(promise: nil)
    }
    
}
