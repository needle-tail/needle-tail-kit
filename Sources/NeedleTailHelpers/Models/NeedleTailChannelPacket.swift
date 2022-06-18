//
//  File.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation
import CypherMessaging

public struct NeedleTailChannelPacket: Codable {
    public let name: String
    public let admin: Username
    public let organizers: Set<Username>
    public let members: Set<Username>
    public let permissions: IRCChannelMode
    
    public init(
        name: String,
        admin: Username,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) {
        self.name = name
        self.admin = admin
        self.organizers = organizers
        self.members = members
        self.permissions = permissions
    }
}
