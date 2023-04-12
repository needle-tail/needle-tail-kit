//
//  NeedleTailEmitter.swift
//
//
//  Created by Cole M on 4/21/22.
//

import CypherMessaging
import NeedleTailHelpers

#if (os(macOS) || os(iOS))
public final class ContactsBundle: ObservableObject {
    
    @Published public var contactListBundle: ContactBundle?
    @Published public var contactBundle: ContactBundle?
    @Published public var contactBundleViewModel = [ContactBundle]()
    @Published public var scrollToBottom: UUID?
    
    public struct ContactBundle: @unchecked Sendable, Equatable, Hashable, Identifiable {
        public let id = UUID()
        public var contact: Contact
        public var privateChat: PrivateChat
        public var groupChats: [GroupChat]
        public var cursor: AnyChatMessageCursor
        public var messages: [AnyChatMessage]
        public var mostRecentMessage: MostRecentMessage<PrivateChat>?
        internal var sortedBy: ContactListSorted = .unPinRead
        
        public static func == (lhs: ContactBundle, rhs: ContactBundle) -> Bool {
            return lhs.id == rhs.id
        }
        
        public func hash(into hasher: inout Hasher) {
            id.hash(into: &hasher)
        }
        
        @MainActor
        public func isPinned() -> Bool {
            privateChat.isPinned
        }
        
        @MainActor
        public func isMarkedUnread() -> Bool {
            privateChat.isMarkedUnread
        }
    }
    
    internal enum ContactListSorted: Comparable {
        case unRead, pinned, unPinRead
    }
    
    
    
    @MainActor
    public func arrangeBundle() {
        var storedContacts = contactBundleViewModel
        contactBundleViewModel.removeAll()
        
        for bundle in storedContacts {
            var bundle = bundle
            if bundle.isPinned() && !bundle.isMarkedUnread() {
                bundle.sortedBy = .pinned
            } else if bundle.isPinned() && bundle.isMarkedUnread() {
                bundle.sortedBy = .unRead
            } else if !bundle.isPinned() && bundle.isMarkedUnread() {
                bundle.sortedBy = .unRead
            } else if !bundle.isPinned() && !bundle.isMarkedUnread() {
                bundle.sortedBy = .unPinRead
            }
            contactBundleViewModel.append(bundle)
        }
        
        var indexOfUnread = 0
        var lastUnread = 0
        
        for setBundle in contactBundleViewModel {
            guard let index = contactBundleViewModel.firstIndex(where: { $0.contact.username == setBundle.contact.username }) else { return }
            switch setBundle.sortedBy {
            case .unRead:
                contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset: indexOfUnread)
                indexOfUnread += 1
                lastUnread = indexOfUnread
            case .pinned:
                contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset:lastUnread + 1)
            case .unPinRead:
                contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset: contactBundleViewModel.count)
            }
        }
        storedContacts.removeAll()
    }
}

public final class MostRecentMessage<Chat: AnyConversation>: ObservableObject {
    
    @Published public var message: AnyChatMessage?
    let chat: Chat
    
    public init(chat: Chat, emitter: NeedleTailEmitter) async throws {
        self.chat = chat
        let cursor = try await chat.cursor(sortedBy: .descending)
        let message = try await cursor.getNext()
        
        if message?.raw.encrypted.conversationId == chat.conversation.id {
            self.message = message
        }
    }
}


#endif

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
    @Published public var dismissRegistration: Bool = false
    @Published public var showProgress: Bool = false
    @Published public var state: TransportState.State = .clientOffline
    
    @Published public var conversationChanged: AnyConversation?
    @Published public var conversationAdded: AnyConversation?
    @Published public var contactToDelete: Contact?
    @Published public var contactToUpdate: Contact?
    @Published public var deleteContactAlert: Bool = false
    @Published public var clearChatAlert: Bool = false
    
    @NeedleTailTransportActor
    public let consumer = ConversationConsumer()
    @Published public var cypher: CypherMessenger?
    @Published public var groupChats = [GroupChat]()
    @Published public var bundles = ContactsBundle()
    @Published public var readReceipts = false
    @Published public var salt = ""
//    @Published public var readMessage = false
    
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
    ) async {
        do {
            try await fetchConversations(cypher)
            for try await result in ConversationSequence(consumer: consumer) {
                switch result {
                case .success(let result):
                    switch result {
                    case .privateChat(let privateChat):
                        
                        var messsages: [AnyChatMessage] = []
                        
                        guard let username = contact?.username else { return }
                        if privateChat.conversation.members.contains(username) {
                            let cursor = try await privateChat.cursor(sortedBy: .descending)
                            
                            let nextBatch = try await cursor.getMore(50)
                            messsages.append(contentsOf: nextBatch)
                            
                            guard let contact = contact else { return }
                            let bundle = ContactsBundle.ContactBundle(
                                contact: contact,
                                privateChat: privateChat,
                                groupChats: [],
                                cursor: cursor,
                                messages: messsages,
                                mostRecentMessage: try await MostRecentMessage(
                                    chat: privateChat,
                                    emitter: self
                                )
                            )

                            if bundles.contactBundleViewModel.contains(where: { $0.contact.username == bundle.contact.username }) {
                                guard let index = bundles.contactBundleViewModel.firstIndex(where: { $0.contact.username == bundle.contact.username }) else { return }
                                bundles.contactBundleViewModel[index] = bundle
                            } else {
                                bundles.contactBundleViewModel.append(bundle)
                            }
                            bundles.arrangeBundle()
                        }
                    case .groupChat(let groupChat):
                        if !groupChats.contains(groupChat) {
                            groupChats.append(groupChat)
                        }
                    case .internalChat(_):
                        return
                    }
                case .retry:
                    return
                case .finished:
                    return
                }
            }
        } catch {
            print(error)
        }
        return
    }
    
    public func removeMessages(from contact: Contact) async throws {
        let conversations = try await cypher?.listConversations(
            includingInternalConversation: false,
            increasingOrder: sortChats
        )
        
        for conversation in conversations ?? [] {
            
            switch conversation {
            case .privateChat(let privateChat):
                let partnerUsername = await contact.username
                guard let username = cypher?.username else { return }
                let conversationPartner = await privateChat.conversation.members.contains(partnerUsername)
                if await privateChat.conversation.members.contains(username) && conversationPartner {
                    for message in try await privateChat.allMessages(sortedBy: .descending) {
                        try await message.remove()
                    }
                }
            default:
                break
            }
        }
        await fetchChats(cypher: cypher!, contact: contact)
    }
    
    
    //MARK: Outbound
    public func sendMessage(privateChat: PrivateChat, message: String) async throws {
        _ = try await privateChat.sendRawMessage(
            type: .text,
            text: message,
            destructionTimer: nil,
            preferredPushType: .message
        )
    }
    
    public func sendGroupMessage(message: String) async throws {
        
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
