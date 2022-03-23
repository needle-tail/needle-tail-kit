//
//  IRCService+Model.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging

extension IRCService {

    enum MessageType: String, Codable {
        case message = "a"
        case multiRecipientMessage = "b"
        case readReceipt = "c"
        case ack = "d"
    }

    struct DirectMessagePacket: Codable {
        let _id: ObjectId
        let messageId: String
        let createdAt: Date
        let sender: UserDeviceId
        let recipient: UserDeviceId
        let message: RatchetedCypherMessage
    }
    
    struct ReadReceiptPacket: Codable {
        enum State: Int, Codable {
            case received = 0
            case displayed = 1
        }
        
        let _id: ObjectId
        let messageId: String
        let state: State
        let sender: UserDeviceId
        let recipient: UserDeviceId
    }
}

public struct RegistrationAck: Codable {
    public var registered: Bool
}
