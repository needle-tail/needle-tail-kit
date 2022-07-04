//
//  MessageModel.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
@preconcurrency import CypherMessaging
import JWTKit

public enum MessageType: Codable, Sendable {
    case publishKeyBundle(String)
    case registerAPN(String)
    case message
    case multiRecipientMessage
    case readReceipt
    case ack(String)
    case blockUnblock
    case beFriend
    case newDevice(String)
    case requestRegistry(String)
    case acceptedRegistry(String)
    case isOffline(String)
    case temporarilyRegisterSession
    case rejectedRegistry(String)
}

public struct MessagePacket: Codable, Sendable {
    public let id: String
    public let pushType: PushType
    public let type: MessageType
    public let createdAt: Date
    public let sender: DeviceId?
    public let recipient: DeviceId?
    public let message: RatchetedCypherMessage?
    public let readReceipt: ReadReceiptPacket?
    public let channelName: String?
    
    public init(
        id: String,
        pushType: PushType,
        type: MessageType,
        createdAt: Date,
        sender: DeviceId?,
        recipient: DeviceId?,
        message: RatchetedCypherMessage?,
        readReceipt: ReadReceiptPacket?,
        channelName: String? = nil
    ) {
        self.id = id
        self.pushType = pushType
        self.type = type
        self.createdAt = createdAt
        self.sender = sender
        self.recipient = recipient
        self.message = message
        self.readReceipt = readReceipt
        self.channelName = channelName
    }
}

