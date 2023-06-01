//
//  MessageModel.swift
//
//
//  Created by Cole M on 3/4/22.
//

//
import CypherMessaging

public enum MessageType: Codable, Sendable {
    case publishKeyBundle(Data)
    case registerAPN(Data)
    case message
    case multiRecipientMessage
    case readReceipt
    case ack(Data)
    case blockUnblock
    case newDevice(NewDeviceState)
    case requestRegistry
    case acceptedRegistry(Data)
    case isOffline(Data)
    case temporarilyRegisterSession
    case rejectedRegistry(Data)
    case notifyContactRemoval
}

public enum AddDeviceType: Codable, Sendable {
    case master, child
}

public struct MultipartMessagePacket: Codable, Sendable {
    public var id: String
    public var sender: NeedleTailNick
    public var recipient: NeedleTailNick?
    public var message: RatchetedCypherMessage?
    public var partNumber: Int
    public var totalParts: Int
    
    public init(
        id: String,
        sender: NeedleTailNick,
        recipient: NeedleTailNick? = nil,
        message: RatchetedCypherMessage? = nil,
        partNumber: Int,
        totalParts: Int
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.message = message
        self.partNumber = partNumber
        self.totalParts = totalParts
    }
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
    public let multipartMessage: MultipartMessagePacket?
    
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
        childDeviceConfig: UserDeviceConfig? = nil,
        multipartMessage: MultipartMessagePacket? = nil
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
        self.multipartMessage = multipartMessage
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

