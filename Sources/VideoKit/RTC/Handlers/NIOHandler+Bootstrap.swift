//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore
import NIOTransportServices

extension NIOHandler {
    
    
    func clientBootstrap() throws -> NIOTSDatagramBootstrap {
        let bootstrap: NIOTSDatagramBootstrap
        //        guard let host = options.hostname else { throw IRCClientError.nilHostname }
        if !options.tls {
            bootstrap = NIOTSDatagramBootstrap(group: self.elg)
            //            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: false)
        } else {
            bootstrap = NIOTSDatagramBootstrap(group: self.elg)
            //            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: true)
        }
        return bootstrap
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
                guard let strongSelf = self else {
                    let error = channel.eventLoop.makePromise(of: Void.self)
                    error.fail(VideoErrors.internalInconsistency)
                    return error.futureResult
                }
                
                return channel.pipeline
                    .addHandler(VideoChannelHandler())
                    .flatMap { [weak self] _ in
                        print(channel.pipeline, "pipeline")
                        let c = channel.pipeline
                            .addHandler(Handler(client: self!))
                        print(c, "Handler pipe")
                        return c
                    }
            }
    }
    
}
