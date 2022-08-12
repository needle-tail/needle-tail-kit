//
//  AuthPacket.swift
//  
//
//  Created by Cole M on 7/18/22.
//

import Foundation
import CypherMessaging

public struct AuthPacket: Codable, @unchecked Sendable {
    public let jwt: String?
    public let appleToken: String?
    public let apnToken: String?
    public let username: Username?
    public let recipient: Username?
    public let deviceId: DeviceId?
    public let config: UserConfig?
    public let tempRegister: Bool?
    public let recipientDeviceId: DeviceId?
    
    public init(
        jwt: String? = nil,
        appleToken: String? = nil,
        apnToken: String? = nil,
        username: Username? = nil,
        recipient: Username? = nil,
        deviceId: DeviceId? = nil,
        config: UserConfig? = nil,
        tempRegister: Bool? = nil,
        recipientDeviceId: DeviceId? = nil
    ) {
        self.jwt = jwt
        self.appleToken = appleToken
        self.apnToken = apnToken
        self.username = username
        self.recipient = recipient
        self.deviceId = deviceId
        self.config = config
        self.tempRegister = tempRegister
        self.recipientDeviceId = recipientDeviceId
    }
}
