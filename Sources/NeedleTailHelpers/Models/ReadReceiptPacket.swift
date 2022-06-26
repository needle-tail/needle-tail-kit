//
//  ReadReceiptPacket.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation
import CypherMessaging

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