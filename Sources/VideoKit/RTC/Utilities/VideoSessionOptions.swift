//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation

public final class VideoSessionOptions {
    
    let id: UUID
    var tls: Bool
    
    init(
        id: UUID,
        tls: Bool
    ) {
        self.id = id
        self.tls = tls
    }
}
