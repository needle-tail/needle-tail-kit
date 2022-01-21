////
////  UDPNIOHandler.swift
////  
////
////  Created by Cole M on 10/9/21.
////
//
//import Foundation
//import NIOCore
//import NIOIRC
//
//internal final class UDPNIOHandler {
//    
//    let groupManager: EventLoopGroupManager
//    internal var group:       EventLoopGroup
//    internal var eventLoop: EventLoop
//    internal var options    : VideoClientOptions
//    internal var retryInfo  = RetryInfo()
////    internal var state      : User = .disconnected
//    internal var userMode   = IRCUserMode()
//    public var delegate     : VideoDelegate?
//    internal var remoteAddress: SocketAddress? = nil
//    
//    init(
//            options: VideoClientOptions,
//            groupProvider provider: EventLoopGroupManager.Provider,
//            group: EventLoopGroup
//    ) {
//        self.group = group
//        self.groupManager = EventLoopGroupManager(provider: provider)
//        self.eventLoop = self.group.next()
//        self.options = options
//    }
//    
//    func createRemoteAddress() throws -> SocketAddress {
//        var sa: SocketAddress?
//        do {
//        sa = try SocketAddress.makeAddressResolvingHost(self.options.host ?? "localhost", port: 9999)
//        } catch {
//            print(error)
//        }
//        guard let address = sa else { throw VideoErrors.remoteAddressNil }
//        return address
//    }
//}
