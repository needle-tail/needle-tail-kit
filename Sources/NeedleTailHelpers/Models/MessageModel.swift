//
//  MessageModel.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging
import JWTKit

public enum MessageType: Codable {
    case publishKeyBundle(String)
    case registerAPN(String)
    case message
    case multiRecipientMessage
    case readReceipt
    case ack(String)
    case blockUnblock
    case beFriend
}

public struct MessagePacket: Codable {
    public let id: String
    public let pushType: PushType
    public let type: MessageType
    public let createdAt: Date
    public let sender: DeviceId?
    public let recipient: DeviceId?
    public let message: RatchetedCypherMessage?
    public let readReceipt: ReadReceiptPacket?
    
    public init(
        id: String,
        pushType: PushType,
        type: MessageType,
        createdAt: Date,
        sender: DeviceId?,
        recipient: DeviceId?,
        message: RatchetedCypherMessage?,
        readReceipt: ReadReceiptPacket?
    ) {
        self.id = id
        self.pushType = pushType
        self.type = type
        self.createdAt = createdAt
        self.sender = sender
        self.recipient = recipient
        self.message = message
        self.readReceipt = readReceipt
    }
}

public struct ReadReceiptPacket: Codable {
    public enum State: Int, Codable {
        case received = 0
        case displayed = 1
    }
    
    public let _id: ObjectId
    public let messageId: String
    public let state: State
    public let sender: UserDeviceId
    public let recipient: UserDeviceId
}

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

public struct Token: JWTPayload {
    public let device: UserDeviceId
    public let exp: ExpirationClaim
    
    public init(
        device: UserDeviceId,
        exp: ExpirationClaim
    ) {
        self.device = device
        self.exp = exp
    }
    
    public func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}
