//
//  UserStatus.swift
//  
//
//  Created by Cole M on 3/31/22.
//

import Foundation
import BSON

public enum UserStatus {
    case wasOffline(ChatDocument)
    case isOnline
}

public struct ChatDocument: Codable {
    public let _id: ObjectId
    public let messageId: String
    public let createdAt: Date
    public let recipients: [IRCMessageRecipient]
    public let chatData: Data
    public let sent: Bool

    public init(
        messageId: String,
        recipients: [IRCMessageRecipient],
        chatData: Data,
        sent: Bool
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.recipients = recipients
        self.chatData = chatData
        self.sent = sent
    }
}
