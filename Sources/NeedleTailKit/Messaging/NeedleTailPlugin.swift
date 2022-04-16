//
//  NeedleTailPlugin.swift
//  
//
//  Created by Cole M on 4/15/22.
//

import Foundation
import MessagingHelpers
import CypherMessaging


extension Notification.Name {
    public static let newChat = Notification.Name("newChat")
}


//Our Store for loading receiving messages in real time
public actor NeedleTailPlugin: Plugin {
    
    public static let pluginIdentifier = "needletail"
    
    @MainActor public let consumer = ConversationConsumer()
    public private(set) var conversations = [TargetConversation.Resolved]()
    public fileprivate(set) var contacts = [Contact]()
    @MainActor public var selectedChat: PrivateChat?
    @MainActor public var sessions = [PrivateChat]()
    @MainActor public var chats = [AnyChatMessage]()
    private let sortChats: @Sendable @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    
    
    public init(sortChats: @escaping @Sendable @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool) {
        self.sortChats = sortChats
    }
    
    nonisolated public func onCreateChatMessage(_ messsage: AnyChatMessage) {
        NotificationCenter.default.post(name: .newChat, object: nil)
    }
    
    public func fetchConversations(_
                            messenger: CypherMessenger
    ) async throws {
        let conversations = try await messenger.listConversations(
            includingInternalConversation: true,
            increasingOrder: sortChats
        )
        await consumer.feedConsumer(conversations)
    }
    
    public func fetchContacts(_ messenger: CypherMessenger) async throws -> [Contact] {
        return try await messenger.listContacts()
    }
    
    public func fetchConversationConsumer() async throws -> SequenceResult? {
        var iterator = ConversationSequence(consumer: consumer).makeAsyncIterator()
        return try await iterator.next()
    }
    
    @MainActor
    public func fetchChats(
        messenger: CypherMessenger,
        contact: Contact? = nil
    ) async {
        do {
            try await fetchConversations(messenger)
            let result = try await fetchConversationConsumer()
                switch result {
                case .success(let result):
                    switch result {
                    case .privateChat(let privateChat):
                        //Append Sessions no matter what
                        sessions.append(privateChat)
                        
                        //Append Chats on a per user selected basis
                        guard let username = contact?.username else { return }
                        if privateChat.conversation.members.contains(username) {
                        selectedChat = privateChat
                        let messages = try await privateChat.cursor(sortedBy: .descending).getMore(50)
                        chats.append(contentsOf: messages)
                        }
                    case .groupChat(_):
                        return
                    case .internalChat(_):
                        return
                    }
                case .retry:
                    return
                case .finished:
                    return
                default:
                    return
                }
        } catch {
            print(error)
        }
        return
    }
}

extension PrivateChat: Hashable, Identifiable {
    public var id: ObjectIdentifier {
        ObjectIdentifier(conversation)
    }
    
    public static func == (lhs: PrivateChat, rhs: PrivateChat) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

extension AnyChatMessage: Hashable, Identifiable {
    public var id: UUID {
        raw.id
    }
    
    public static func == (lhs: AnyChatMessage, rhs: AnyChatMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}
