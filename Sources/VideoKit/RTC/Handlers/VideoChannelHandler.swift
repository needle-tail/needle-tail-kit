//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore


internal final class VideoChannelHandler: ChannelDuplexHandler {
//    public typealias InboundErr  = IRCParserError
    
    public typealias InboundIn   = ByteBuffer
//    public typealias InboundOut  = IRCMessage
    
    public typealias OutboundIn  = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    
    init() {
        
    }
}
