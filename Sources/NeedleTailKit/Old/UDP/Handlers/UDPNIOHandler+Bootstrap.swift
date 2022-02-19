////
////  UDPNIOHandler+Bootstrap.swift
////  
////
////  Created by Cole M on 10/9/21.
////
//
//import Foundation
//import NIOCore
//import NIOTransportServices
//
//extension UDPNIOHandler {
//    
//    
//    func clientBootstrap() throws -> NIOClientTCPBootstrap {
//        let bootstrap: NIOClientTCPBootstrap
//        guard let host = options.host else { throw IRCClientError.nilHostname }
//        if !options.tls {
//            bootstrap = try groupManager.makeUDPBootstrap(hostname: host, useTLS: false)
//        } else {
//            bootstrap = try groupManager.makeUDPBootstrap(hostname: host, useTLS: true)
//        }
//        return bootstrap
//            .connectTimeout(.hours(1))
//            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
//            .channelInitializer { [weak self] channel in
//                guard let strongSelf = self else {
//                    let error = channel.eventLoop.makePromise(of: Void.self)
//                    error.fail(VideoErrors.internalInconsistency)
//                    return error.futureResult
//                }
//              
//                return channel.pipeline
//                    .addHandler(VideoChannelHandler(remoteAddress: try! strongSelf.createRemoteAddress()))
//            }
//    }
//    
//}
