//
//  AuthPacket.swift
//
//
//  Created by Cole M on 7/18/22.
//

import CypherMessaging

public struct AuthPacket: Codable, @unchecked Sendable {
    public let jwt: String?
    public let appleToken: String?
    public let apnToken: String?
    //Always the Client's NTKUser
    public let ntkUser: NTKUser?
    //Always a Contact to look up. (i.e. via Reading Key bundles)
    public let ntkContact: NTKContact?
    public let config: UserConfig?
    public let tempRegister: Bool?
    public let recipientDeviceId: DeviceId?
    
    public init(
        jwt: String? = nil,
        appleToken: String? = nil,
        apnToken: String? = nil,
        ntkUser: NTKUser? = nil,
        ntkContact: NTKContact? = nil,
        config: UserConfig? = nil,
        tempRegister: Bool? = nil,
        recipientDeviceId: DeviceId? = nil
    ) {
        self.jwt = jwt
        self.appleToken = appleToken
        self.apnToken = apnToken
        self.ntkUser = ntkUser
        self.ntkContact = ntkContact
        self.config = config
        self.tempRegister = tempRegister
        self.recipientDeviceId = recipientDeviceId
    }
}
