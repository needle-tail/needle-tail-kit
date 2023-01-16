//
//  NeedleTailHandler.swift
//  
//
//  Created by Cole M on 4/21/22.
//

import Foundation
import CypherMessaging
import NeedleTailHelpers

public class NeedleTailRepository {
    @NeedleTailTransportActor public let consumer = ConversationConsumer()
    @MainActor public var selectedChat: PrivateChat?
    @MainActor public var cypher: CypherMessenger?
    @MainActor public var sessions = [PrivateChat]()
    @MainActor public var groupChats = [GroupChat]()
    @MainActor public var cursor: AnyChatMessageCursor?
    @MainActor public var chats: [AnyChatMessage] = []
    
    let sortChats: @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    
    public init(sortChats: @escaping @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool) {
        self.sortChats = sortChats
    }
    
    //MARK: Inbound
    @MainActor
    public func fetchConversations(_
                                   cypher: CypherMessenger
    ) async throws {
        
        let conversations = try await cypher.listConversations(
            includingInternalConversation: true,
            increasingOrder: sortChats
        )
        await consumer.feedConsumer(conversations)
    }

    public func fetchContacts(_ cypher: CypherMessenger) async throws -> [Contact] {
        try await cypher.listContacts()
    }
    
    public func fetchGroupChats(_ cypher: CypherMessenger) async throws -> [GroupChat] {
        return await groupChats
    }
    
    @MainActor
    /// `fetchChats()` will fetch all CTK/NTK chats/chat types. That means when this method is called we will get all private chats for the CTK Instance which means all chats on our localDB
    /// that this device has knowledge of. We then can use them in our NeedleTailKit Transport Mechanism.
    /// - Parameters:
    ///   - cypher: **CTK**'s `CypherMessenger` for this Device.
    ///   - contact: The opitional `Contact` we want to use to filter private chats on.
    /// - Returns: An `AnyChatMessageCursor` which references a point in memory of `CypherMessenger`'s `AnyChatMessage`
    public func fetchChats(
        cypher: CypherMessenger,
        contact: Contact? = nil
    ) async -> AnyChatMessageCursor? {
        do {
            try await fetchConversations(cypher)
            do {
                for try await result in ConversationSequence(consumer: consumer) {
                    
                    switch result {
                    case .success(let result):
                        switch result {
                        case .privateChat(let privateChat):
                            //Append Sessions no matter what
                            if !sessions.contains(privateChat) {
                                sessions.append(privateChat)
                            }
                            guard let username = contact?.username else { return nil }
                            if privateChat.conversation.members.contains(username) {
                                selectedChat = privateChat
                                self.cursor = try await privateChat.cursor(sortedBy: .descending)
                                self.chats = try await privateChat.allMessages(sortedBy: .descending)
                                return self.cursor
                            }
                        case .groupChat(let groupChat):
                            if !groupChats.contains(groupChat) {
                                groupChats.append(groupChat)
                            }
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
    
    public func sendGroupMessage(message: String) async throws {

    }
    
    public func deleteContact(_ contact: Contact) async throws {
        try await contact.remove()
    }
    
}
