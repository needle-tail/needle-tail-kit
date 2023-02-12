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
    case registerAPN(Data)
    case message
    case multiRecipientMessage
    case readReceipt
    case ack(String)
    case blockUnblock
    case newDevice(NewDeviceState)
    case requestRegistry
    case acceptedRegistry(String)
    case isOffline(String)
    case temporarilyRegisterSession
    case rejectedRegistry(String)
}

public enum AddDeviceType: Codable, Sendable {
    case master, child
}

public struct MessagePacket: Codable, Sendable {
    public let id: String
    public let pushType: PushType
    public var type: MessageType
    public let createdAt: Date
    public let sender: DeviceId?
    public let recipient: DeviceId?
    public let message: RatchetedCypherMessage?
    public let readReceipt: ReadReceipt?
    public let channelName: String?
    public let addKeyBundle: Bool?
    public let contacts: [NTKContact]?
    public let addDeviceType: AddDeviceType?
    public let childDeviceConfig: UserDeviceConfig?
    
    public init(
        id: String,
        pushType: PushType,
        type: MessageType,
        createdAt: Date,
        sender: DeviceId?,
        recipient: DeviceId?,
        message: RatchetedCypherMessage?,
        readReceipt: ReadReceipt?,
        channelName: String? = nil,
        addKeyBundle: Bool? = nil,
        contacts: [NTKContact]? = nil,
        addDeviceType: AddDeviceType? = nil,
        childDeviceConfig: UserDeviceConfig? = nil
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
        self.addKeyBundle = addKeyBundle
        self.contacts = contacts
        self.addDeviceType = addDeviceType
        self.childDeviceConfig = childDeviceConfig
    }
}

public struct NTKContact: Codable, Sendable {
    public var username: Username
    public var nickname: String
    
    public init(username: Username, nickname: String) {
        self.username = username
        self.nickname = nickname
    }
}

