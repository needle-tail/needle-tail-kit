//
//  IRCHandler.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIO
import NIOIRC


final class IRCHandler: ChannelInboundHandler {
    
    typealias InboundIn = IRCMessage
    
    let client : IRCClient
    
    init(client: IRCClient) {
        self.client = client
    }
    
    func channelActive(context: ChannelHandlerContext) {
        print("Channel is Active")
    }
    func channelInactive(context: ChannelHandlerContext) {
        print("Channel is InActive")
        client.handlerDidDisconnect(context)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("Read Channel")
        let value = unwrapInboundIn(data)
        client.handlerHandleResult(value)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error caught \(error)")
        self.client.handlerCaughtError(error, in: context)
        context.close(promise: nil)
    }
}
