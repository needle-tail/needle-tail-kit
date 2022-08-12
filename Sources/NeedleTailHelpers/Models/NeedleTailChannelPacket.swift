//
//  NeedleTailChannelPacket.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation
import CypherMessaging

public struct NeedleTailChannelPacket: Codable, Sendable {
    public let name: String
    public let admin: NeedleTailNick
    public let organizers: Set<Username>
    public let members: Set<Username>
    public let permissions: IRCChannelMode
    public let destroy: Bool?
    public let partMessage: String?
    public let blobId: String?
    
    public init(
        name: String,
        admin: NeedleTailNick,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode,
        destroy: Bool? = false,
        partMessage: String? = nil,
        blobId: String? = nil
    ) {
        self.name = name
        self.admin = admin
        self.organizers = organizers
        self.members = members
        self.permissions = permissions
        self.destroy = destroy
        self.partMessage = partMessage
        self.blobId = blobId
    }
}
