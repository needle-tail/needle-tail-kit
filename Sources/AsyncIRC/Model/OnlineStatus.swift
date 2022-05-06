//
//  UserStatus.swift
//  
//
//  Created by Cole M on 3/31/22.
//

import Foundation
import BSON

public enum OnlineStatus {
    case wasOffline(ChatDocument)
    case isOnline
}

public struct ChatDocument: Codable {
    public let id: String
    public let createdAt: Date
    public let sender: String
    public let recipients: [IRCMessageRecipient]
    public let chatData: Data
    public var sent: Bool

    public init(
        id: String,
        sender: String,
        recipients: [IRCMessageRecipient],
        chatData: Data,
        sent: Bool
    ) {
        self.id = id
        self.createdAt = Date()
        self.sender = sender
        self.recipients = recipients
        self.chatData = chatData
        self.sent = sent
    }
}
