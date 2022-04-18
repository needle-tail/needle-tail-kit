//
//  IRCService+Model.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging

public enum MessageType: String, Codable {
    case message = "a"
    case multiRecipientMessage = "b"
    case readReceipt = "c"
    case ack = "d"
    case blockUnblock = "e"
}

public struct MessagePacket: Codable {
    public let id: String
    public let pushType: PushType
    public let type: MessageType
    public let createdAt: Date
    public let sender: DeviceId
    public let recipient: DeviceId
    public let message: RatchetedCypherMessage
    public let readReceipt: ReadReceiptPacket?
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
