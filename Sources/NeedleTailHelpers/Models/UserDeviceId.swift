//
//  UserDeviceId.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation
import CypherMessaging

public struct UserDeviceId: Hashable, Codable {
    public let user: Username
    public let device: DeviceId
    
    public init(
        user: Username,
        device: DeviceId
    ) {
        self.user = user
        self.device = device
    }
}
