//
//  VideoChannelHandler.swift
//  
//
//  Created by Cole M on 10/9/21.
//
#if os(iOS) || os(macOS)
import Foundation
import NIOCore


internal final class VideoChannelHandler: ChannelDuplexHandler {
    
    public typealias InboundIn   = AddressedEnvelope<ByteBuffer>
    
    public typealias OutboundIn  = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let remoteAddress: SocketAddress
    private var numBytes = 0
    
    init(remoteAddress: SocketAddress) {
        self.remoteAddress = remoteAddress
    }
    
    internal func channelActive(context: ChannelHandlerContext) {
            let line = readLine(strippingNewline: true)!
            let buffer = context.channel.allocator.buffer(string: line)
            
            self.numBytes = buffer.readableBytes
            let envelope = AddressedEnvelope<ByteBuffer>(remoteAddress: self.remoteAddress, data: buffer)
            context.writeAndFlush(self.wrapOutboundOut(envelope), promise: nil)
    }
    
    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        let byteBuffer = envelope.data
        
        if self.numBytes <= 0 {
            let string = String(buffer: byteBuffer)
            print("Received: '\(string)' back from server, closing channel")
            context.close(promise: nil)
        }
    }
    
    internal func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: \(error)")
        
        context.close(promise: nil)
    }
    
}
#endif
