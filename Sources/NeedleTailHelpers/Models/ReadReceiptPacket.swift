//
//  ReadReceiptPacket.swift
//
//
//  Created by Cole M on 6/18/22.
//

import CypherMessaging

public struct NTKUser: Hashable, Codable, Sendable {
    public var username: Username
    public var deviceId: DeviceId
    
    public init(username: Username, deviceId: DeviceId) {
        self.username = username
        self.deviceId = deviceId
    }
}

public struct ReadReceipt: Codable, Sendable {
    public enum State: Int, Codable, Sendable {
        case received = 0
        case displayed = 1
    }
    
    public let messageId: String
    public let state: State
    public let sender: NTKUser
    public let recipient: NTKUser
    public let receivedAt: Date
    
    public init(
        messageId: String,
        state: State,
        sender: NTKUser,
        recipient: NTKUser,
        receivedAt: Date
    ) {
        self.messageId = messageId
        self.state = state
        self.sender = sender
        self.recipient = recipient
        self.receivedAt = receivedAt
    }
}
