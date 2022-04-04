////
////  UDPHandler.swift
////  
////
////  Created by Cole M on 10/9/21.
////
//
//import Foundation
//import NIO
//
//
//
//final class UDPHandler: ChannelInboundHandler {
//    
//    typealias InboundIn = ByteBuffer
//    
//    let client : UDPNIOHandler
//    
//    init(client: UDPNIOHandler) {
//        self.client = client
//    }
//    
//    func channelActive(context: ChannelHandlerContext) {
//        print("Channel is Active")
//    }
//    func channelInactive(context: ChannelHandlerContext) {
//        print("Channel is InActive")
////        client.handlerDidDisconnect(context)
//    }
//    
//    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        print("Read Channel")
////        let value = unwrapInboundIn(data)
////        client.handlerHandleResult(value)
//    }
//    
//    func errorCaught(context: ChannelHandlerContext, error: Error) {
//        print("error caught \(error)")
////        self.client.handlerCaughtError(error, in: context)
//        context.close(promise: nil)
//    }
//}
