//
//  RTCPeerConnection.swift
//  
//
//  Created by Cole M on 2/13/22.
//

import Foundation
import NIOSSL
import NIO

final public class RTCPeerConnection: ChannelDuplexHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    
    
    
//    internal let factory: RTCPeerConnectionFactory?
//    internal let localStream: RTCMediaStream?
//    internal let mediaConstraints: // TODO: - Define
//    internal weak var delegate: RTCPeerConnectionDelegate?
    
    public init(
//        factory: RTCPeerConnectionFactory?,
//        configuration: RTCConfiguration,
//        constraints: //TODO: - Define,
//        delegate: RTCPeerConnectionDelegate?
    ) {
//        self.factory = factory
//        self.configuration = configuration
//        self.constraints = constraints
//        self.delegate = delegate
    }
    
    
    /// Creates an X.509 certificate and corresponding private key, returning a promise that resolves with the new RTCCertificate once it's generated.
    class func generateCertificate() -> RTCCertificate {
        return RTCCertificate()
    }
    
    
    
}


final internal class RTCCertificate {
    
    
    
    
    
}
