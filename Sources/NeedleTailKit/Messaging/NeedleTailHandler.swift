//
//  NeedleTailHandler.swift
//  
//
//  Created by Cole M on 4/21/22.
//
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
import Foundation
import CypherMessaging

public class NeedleTailHandler {
    @MainActor public let consumer = ConversationConsumer()
    @MainActor public var selectedChat: PrivateChat?
    @MainActor public var sessions = [PrivateChat]()
    @MainActor public var cursor: AnyChatMessageCursor?
    @MainActor public var chats: [AnyChatMessage] = []
    
    private let sortChats: @Sendable @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    
    public init(sortChats: @escaping @Sendable @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool) {
        self.sortChats = sortChats
    }
    
    //MARK: Inbound
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
        try await messenger.listContacts()
    }
    
    @MainActor
    public func fetchChats(
        messenger: CypherMessenger,
        contact: Contact? = nil
    ) async -> AnyChatMessageCursor? {
        do {
            try await fetchConversations(messenger)
            do {
            for try await result in ConversationSequence(consumer: consumer) {

                switch result {
                case .success(let result):
                    switch result {
                    case .privateChat(let privateChat):
                        print(privateChat)
                        //Append Sessions no matter what
                        sessions.append(privateChat)
                        guard let username = contact?.username else { return nil }
                        if privateChat.conversation.members.contains(username) {
                            selectedChat = privateChat
                            self.cursor = try await privateChat.cursor(sortedBy: .descending)
                            self.chats = try await privateChat.allMessages(sortedBy: .descending)
                            return self.cursor
                        }
                    case .groupChat(_):
                        return nil
                    case .internalChat(_):
                        return nil
                    }
                case .retry:
                    return nil
                case .finished:
                    return nil
                }
            }
            } catch {
                print(error)
            }
        
        } catch {
            print(error)
        }
        return nil
    }

//MARK: Outbound
    public func sendMessage(message: String) async throws {
        _ = try await selectedChat?.sendRawMessage(
            type: .text,
            text: message,
            preferredPushType: .message
        )
    }
    
    public func deleteContact(_ contact: Contact) async throws {
        try await contact.remove()
    }
    
}
#endif
