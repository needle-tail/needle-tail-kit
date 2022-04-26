//
//  NeedleTailNick.swift
//  
//
//  Created by Cole M on 4/26/22.
//

import Foundation
import CypherMessaging

public struct NeedleTailNick: Hashable {
    public var deviceId: DeviceId
    public var nick: IRCNickName
    
    public init(
        deviceId: DeviceId,
        nick: IRCNickName
    ) {
        self.deviceId = deviceId
        self.nick = nick
    }
}
