//
//  BlockUnblock.swift
//  
//
//  Created by Cole M on 4/17/22.
//

import Foundation

public struct BlockUnblock: Codable {
    public var recipient: String
    public var sender: String
    public var senderDeviceId: String
    
    public init(
        recipient: String,
        sender: String,
        senderDeviceId: String
    ) {
        self.recipient = recipient
        self.sender = sender
        self.senderDeviceId = senderDeviceId
    }
}
