//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore


internal final class NIOHandler {
    
    internal var elg: EventLoopGroup
    internal var options: VideoSessionOptions
    
    init(
            options: VideoSessionOptions,
        //    groupProvider provider: EventLoopGroupManager.Provider,
            elg: EventLoopGroup
    ) {
        self.elg = elg
        self.options = options
    }
    
    
}
