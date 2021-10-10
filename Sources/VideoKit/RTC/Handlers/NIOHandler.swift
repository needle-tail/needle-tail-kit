//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore
import NIOIRC

internal final class NIOHandler {
    
    internal var elg:       EventLoopGroup
    internal var eventLoop: EventLoop
    internal var options    : VideoClientOptions
    internal var retryInfo  = RetryInfo()
    internal var state      : StateMachine = .disconnected
    internal var userMode   = IRCUserMode()
    public var delegate     : VideoDelegate?
    internal var remoteAddress: SocketAddress? = nil
    
    init(
            options: VideoClientOptions,
        //    groupProvider provider: EventLoopGroupManager.Provider,
            elg: EventLoopGroup
    ) {
        self.elg = elg
        self.eventLoop = self.elg.next()
        self.options = options
    }
    
    func createRemoteAddress() throws -> SocketAddress {
        var sa: SocketAddress?
        do {
        sa = try SocketAddress.makeAddressResolvingHost(self.options.host ?? "localhost", port: self.options.port)
        } catch {
            print(error)
        }
        guard let address = sa else { throw VideoErrors.remoteAddressNil }
        return address
    }
}
