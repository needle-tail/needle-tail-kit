//
//  NeedleTailEmitter.swift
//
//
//  Created by Cole M on 4/21/22.
//

import CypherMessaging
import NeedleTailHelpers

#if (os(macOS) || os(iOS))
extension NeedleTailEmitter: ObservableObject {}
#endif

//Our Bottom level Store for emitting events between CTK/NTK and Client
public final class NeedleTailEmitter: Equatable, @unchecked Sendable {
    
    public var id = UUID()
#if (os(macOS) || os(iOS))
    
    
    @Published public var messageReceived: AnyChatMessage?
    @Published public var messageRemoved: AnyChatMessage?
    @Published public var messageChanged: AnyChatMessage?
    @Published public var contactChanged: Contact?
    @Published public var registered = false
    @Published public var contactAdded: Contact?
    @Published public var contactRemoved: Contact?
    @Published public var nicksOnline: [NeedleTailNick] = []
    @Published public var partMessage = ""
    @Published public var chatMessageChanged: AnyChatMessage?
    @Published public var needleTailNick: NeedleTailNick?
    @Published public var requestMessageId: String?
    @Published public var qrCodeData: Data?
    @Published public var accountExists: String = ""
    @Published public var showScanner: Bool = false
    @Published public var dismiss: Bool = false
    @Published public var showProgress: Bool = false
    @Published public var state: TransportState.State = .clientOffline
    
    @Published public var conversationChanged: AnyConversation?
    @Published public var conversationAdded: AnyConversation?
    
    
    
    
    @NeedleTailTransportActor public let consumer = ConversationConsumer()
    @Published public var contacts: [Contact] = []
    @Published public var selectedContact: Contact?
    @Published public var selectedChat: PrivateChat?
    @Published public var cypher: CypherMessenger?
    @Published public var sessions = [PrivateChat]()
    @Published public var groupChats = [GroupChat]()
    @Published public var cursor: AnyChatMessageCursor?
    @Published public var messages: [AnyChatMessage] = []
    @Published public var allMessages: [AnyChatMessage] = []
    
    
    
    
    
    
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
        return groupChats
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
                                messages.removeAll()
                                try await getMessages(count: 50)
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
    
    @MainActor
    public func getMessages(count: Int) async throws {
        if let cursor = cursor {
            let nextBatch = try await cursor.getMore(count)
            if !messages.contains(nextBatch) {
                messages.append(contentsOf: nextBatch)
            }
        }
    }
    
    //MARK: Outbound
    public func sendMessage(message: String) async throws {
        _ = try await selectedChat?.sendRawMessage(
            type: .text,
            text: message,
            destructionTimer: nil,
            preferredPushType: .message
        )
    }
    
    public func sendGroupMessage(message: String) async throws {

    }
    
    public func deleteContact(_ contact: Contact) async throws {
        try await contact.remove()
    }
#endif
//    public let onRekey = PassthroughSubject<Void, Never>()
//    public let savedChatMessages = PassthroughSubject<AnyChatMessage, Never>()
//    public let chatMessageRemoved = PassthroughSubject<AnyChatMessage, Never>()
//    public let conversationChanged = PassthroughSubject<TargetConversation.Resolved, Never>()
//    public let contactChanged = PassthroughSubject<Contact, Never>()
//    public let userDevicesChanged = PassthroughSubject<Void, Never>()
//    public let customConfigChanged = PassthroughSubject<Void, Never>()
//    public let p2pClientConnected = PassthroughSubject<P2PClient, Never>()
//    public let conversationAdded = PassthroughSubject<AnyConversation, Never>()
    
    public static func == (lhs: NeedleTailEmitter, rhs: NeedleTailEmitter) -> Bool {
        return lhs.id == rhs.id
    }
}
