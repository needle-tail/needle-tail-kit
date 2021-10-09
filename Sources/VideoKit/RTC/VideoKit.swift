//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore
import NIOTransportServices
import NIOPosix


final public class VideoKit {
    
    internal var videoSession: VideoSession
    internal var elg: EventLoopGroup?
    
    init(videoSession: VideoSession, elg: EventLoopGroup? = nil) {
        self.videoSession = videoSession
        self.elg = elg
        
#if canImport(Network)
        if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            self.elg = NIOTSEventLoopGroup()
        } else {
            self.elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
#else
        self.elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        
        defer {
            try? self.elg?.syncShutdownGracefully()
        }
        
//        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        
        #if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            // Fire up NIO HANDLER
            
//            self.niotsHandler = NIOHandler(options: options, groupProvider: provider, group: group)
//            self.niotsHandler?.delegate = self
        }
        #else
        
        #endif
    }
    
    
    
}
