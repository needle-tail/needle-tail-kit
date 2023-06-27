//
//  MessageModel.swift
//
//
//  Created by Cole M on 3/4/22.
//

//
import CypherMessaging

public enum MessageSubType: String, Sendable {
    case text, audio, image, doc, videoThumbnail, video, group, none
}

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

public struct MultipartMessagePacket: Codable, Sendable, Equatable {
    public var id: String
    public var sender: NeedleTailNick
    public var recipient: NeedleTailNick?
    public var fileName: String
    public var dataCount: Int
    
    public init(
        id: String,
        sender: NeedleTailNick,
        recipient: NeedleTailNick? = nil,
        fileName: String,
        dataCount: Int
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.fileName = fileName
        self.dataCount = dataCount
    }
}

extension CypherMessageType: @unchecked Sendable {}

public struct ChatPacketJob: Sendable {
    
    public var chat: AnyConversation
    public var type: CypherMessageType
    public var messageSubType: String
    public var text: String
    public var metadata: Document
    public var destructionTimer: TimeInterval
    public var preferredPushType: PushType
    public var conversationType: ConversationType
    public var multipartMessage: MultipartMessagePacket
    
    public init(
        chat: AnyConversation,
        type: CypherMessageType,
        messageSubType: String,
        text: String,
        metadata: Document,
        destructionTimer: TimeInterval,
        preferredPushType: PushType,
        conversationType: ConversationType,
        multipartMessage: MultipartMessagePacket
    ) {
        self.chat = chat
        self.type = type
        self.messageSubType = messageSubType
        self.text = text
        self.metadata = metadata
        self.destructionTimer = destructionTimer
        self.preferredPushType = preferredPushType
        self.conversationType = conversationType
        self.multipartMessage = multipartMessage
    }
}

public struct MessagePacket: Codable, Sendable, Equatable {
    
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
    public var multipartMessage: MultipartMessagePacket?
    
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
    
    public static func == (lhs: MessagePacket, rhs: MessagePacket) -> Bool {
        return lhs.id == rhs.id
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

