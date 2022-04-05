//
//  IRCService+Model.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging

    enum MessageType: String, Codable {
        case message = "a"
        case multiRecipientMessage = "b"
        case readReceipt = "c"
        case ack = "d"
    }

    struct MessagePacket: Codable {
        let _id: ObjectId
        let pushType: PushType
        let type: MessageType
        let messageId: String
        let createdAt: Date
        let sender: DeviceId
        let recipient: DeviceId
        let message: RatchetedCypherMessage
        let readReceipt: ReadReceiptPacket?
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
