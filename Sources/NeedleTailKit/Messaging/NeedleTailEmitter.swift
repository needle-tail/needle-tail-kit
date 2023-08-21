//
//  NeedleTailEmitter.swift
//
//
//  Created by Cole M on 4/21/22.
//

import CypherMessaging
@_spi(AsyncChannel) import NeedleTailHelpers

#if (os(macOS) || os(iOS))
public final class ContactsBundle: ObservableObject {
    
    @Published public var contactListBundle: ContactBundle?
    @Published public var contactBundle: ContactBundle?
    @Published public var contactBundleViewModel = [ContactBundle]()
    @Published public var scrollToBottom: UUID?
    
    public struct ContactBundle: Equatable, Hashable, Identifiable {
        public let id = UUID()
        public var contact: Contact
        public var privateChat: PrivateChat
        public var groupChats: [GroupChat]
        public var cursor: AnyChatMessageCursor
        public var messages: [AnyChatMessage]
        public var mostRecentMessage: MostRecentMessage<PrivateChat>?
        internal var sortedBy: ContactListSorted = .unPinRead
        
        public init(
            contact: Contact,
            privateChat: PrivateChat,
            groupChats: [GroupChat],
            cursor: AnyChatMessageCursor,
            messages: [AnyChatMessage],
            mostRecentMessage: MostRecentMessage<PrivateChat>? = nil
        ) {
            self.contact = contact
            self.privateChat = privateChat
            self.groupChats = groupChats
            self.cursor = cursor
            self.messages = messages
            self.mostRecentMessage = mostRecentMessage
        }
        
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

public struct DestructionMetadata: Identifiable {
    
    public let id = UUID()
    public var title: DestructiveMessageTimes
    public var timeInterval: Int
    
    public init(title: DestructiveMessageTimes, timeInterval: Int) {
        self.title = title
        self.timeInterval = timeInterval
    }
}

public enum DestructiveMessageTimes: String {
    case off = "Off"
    case custom = "Custom"
    case thirtyseconds = "30 Seconds"
    case fiveMinutes = "5 Minutes"
    case oneHour = "1 Hours"
    case eightHours = "8 Hours"
    case oneDay = "1 Day"
    case oneWeek = "1 Week"
    case fourWeeks = "4 Weeks"
}


extension NeedleTailEmitter: ObservableObject {}

public struct MultipartDownloadFailed {
    public var status: Bool
    public var error: String
    
    public init(status: Bool, error: String) {
        self.status = status
        self.error = error
    }
}

#endif

public struct Filename: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    
    public var description: String { raw }
    public let raw: String
    
    public init(stringLiteral value: String) {
        self.init(value)
    }
    
    public init(_ description: String) {
        self.raw = description.lowercased()
    }
    
    public static func ==(lhs: Filename, rhs: Filename) -> Bool {
        lhs.raw == rhs.raw
    }
    
    public static func <(lhs: Filename, rhs: Filename) -> Bool {
        lhs.raw < rhs.raw
    }
    
    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}


//Our Bottom level Store for emitting events between CTK/NTK and Client
public final class NeedleTailEmitter: NSObject, @unchecked Sendable {
    public var id = UUID()
    
#if (os(macOS) || os(iOS))
    public static let shared = NeedleTailEmitter(sortChats: sortConversations)
    
    
    @Published public var channelIsActive = false
    @Published public var clientIsRegistered = false
    
    @Published public var messageReceived: AnyChatMessage?
    @Published public var messageRemoved: AnyChatMessage?
    @Published public var messageChanged: AnyChatMessage?
    @Published public var multipartReceived: Data?
    @Published public var multipartUploadComplete: Bool?
    @Published public var multipartDownloadFailed: MultipartDownloadFailed = MultipartDownloadFailed(status: false, error: "")
    @Published public var listedFilenames = Set<Filename>()
    
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
    @Published public var cypher: CypherMessenger?
    @Published public var groupChats = [GroupChat]()
    @Published public var bundles = ContactsBundle()
    @Published public var readReceipts = false
    @Published public var salt = ""
    @Published public var destructionTime: DestructionMetadata?
    //    = UserDefaults.standard.integer(forKey: "destructionTime")
    let consumer = NeedleTailAsyncConsumer<TargetConversation.Resolved>()
    let sortChats: @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    
    public init(sortChats: @escaping @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool) {
        self.sortChats = sortChats
    }
    
    @MainActor
    public func findMessage(by mediaId: String) async -> AnyChatMessage? {
        return await bundles.contactBundle?.messages.async.first(where: { message in
            guard let binary = message.metadata["mediaId"] as? Binary else { return false }
            return String(data: binary.data, encoding: .utf8) == mediaId
        })
    }
    
    @MainActor
    public func findAllMessages(with mediaId: String) async throws -> [AnyChatMessage] {
        var messages = [AnyChatMessage]()
        guard let contactBundle = bundles.contactBundle else { return [] }
        for try await message in contactBundle.messages.async {
            guard let binary = message.metadata["mediaId"] as? Binary else { return [] }
            if String(data: binary.data, encoding: .utf8) == mediaId {
                messages.append(message)
            }
        }
        return messages
    }
    
    //MARK: Inbound
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
            for try await result in NeedleTailAsyncSequence(consumer: consumer) {
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
                    break
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
    public func sendMessage<Chat: AnyConversation>(
        chat: Chat,
        type: CypherMessageType,
        messageSubtype: String? = nil,
        text: String = "",
        metadata: Document = [:],
        destructionTimer: TimeInterval? = nil,
        pushType: PushType = .message,
        conversationType: ConversationType,
        mediaId: String = "",
        sender: NeedleTailNick,
        dataCount: Int = 0
    ) async throws {

        //Create a job for each device we need to upload an object for
       try await self.generatePacketDetails(
            mediaId: "\(messageSubtype ?? "none/*")_\(mediaId)",
            sender: sender,
            dataCount: dataCount,
            chat: chat,
            type: type,
            messageSubType: messageSubtype ?? "none/*",
            text: text,
            metadata: metadata,
            destructionTimer: destructionTimer ?? 0.0,
            pushType: pushType,
            conversationType: conversationType
        )

        //Send Message
        _ = try await chat.sendRawMessage(
            type: type,
            messageSubtype: messageSubtype,
            text: text,
            metadata: metadata,
            destructionTimer: destructionTimer,
            preferredPushType: pushType
        )
    }
    
    func generatePacketDetails(
        mediaId: String,
        sender: NeedleTailNick,
        dataCount: Int,
        chat: AnyConversation,
        type: CypherMessageType,
        messageSubType: String,
        text: String,
        metadata: Document,
        destructionTimer: TimeInterval,
        pushType: PushType,
        conversationType: ConversationType
    ) async throws {
#if (os(macOS) || os(iOS))
        let pc = chat as? PrivateChat
        guard let recipientsDevices = try await NeedleTail.shared.messenger?.readKeyBundle(forUsername: pc!.conversationPartner) else { return }
        //We need to block this if we have a large data count and need to create thumbnail
        if dataCount > 10777216 {
            var fileNameData: Binary?
            if let fileNameBinary = metadata["fileNameBinary"] as? Binary {
                fileNameData = fileNameBinary
            } else if let imageNameBinary = metadata["imageNameBinary"] as? Binary {
                fileNameData = imageNameBinary
            } else if let thumbnailNameBinary = metadata["thumbnailNameBinary"] as? Binary {
                fileNameData = thumbnailNameBinary
            }
            
            //For each device we need to upload an object for that device
            for device in try recipientsDevices.readAndValidateDevices() {
                guard let fileNameData = (String(data: fileNameData?.data ?? Data(), encoding: .utf8)) else { return }
                await NeedleTail.shared.chatJobQueue.addJob(
                    ChatPacketJob(
                        chat: chat,
                        type: type,
                        messageSubType: messageSubType,
                        text: text,
                        metadata: metadata,
                        destructionTimer: destructionTimer,
                        preferredPushType: pushType,
                        conversationType: conversationType,
                        multipartMessage: MultipartMessagePacket(
                            id: mediaId,
                            sender: sender,
                            fileName: "\(fileNameData)_\(device.deviceId.raw)",
                            dataCount: dataCount
                        )
                    )
                )
            }
            
            //Send Thumbail image if we are not video or videoThumbnail
            var message = ""
            switch MessageSubType(rawValue: messageSubType) {
            case .text:
                message = "You have a message you can download. Long press to download..."
            case .audio:
                message = "You have an audio message you can download. Long press to download..."
            case .image:
                message = "You have an image you can download. Long press to download..."
            case .doc:
                message = "You have a document you can download. Long press to download..."
            default:
                break
            }
            
            if messageSubType != "video/*", messageSubType != "videoThumbnail/*" {
                var newMetadata = Document()
                guard let mediaId = metadata["mediaId"] as? Binary else { return }
                
                if messageSubType == "image/*" {
                    if let thumbnailBinary = metadata["thumbnailBlob"] as? Binary {
                        guard let fileNameData = fileNameData?.data else { return }
                        newMetadata = [
                            "mediaId": mediaId,
                            "blob": thumbnailBinary,
                            "fileNameBinary": fileNameData,
                            "fileSize": dataCount
                        ]
                    }
                } else if messageSubType == "doc/*" ||  messageSubType == "audio/*" {
                    
                    guard let fileNameData = fileNameData?.data else { return }
                    guard let fileType = messageSubType.dropLast(2).data(using: .utf8) else { return }
                    
                    newMetadata = try await MessageDataToFilePlugin.createDataToFileMetadata(
                        metadata: DataToFileMetaData(
                            mediaId: mediaId.data,
                            fileNameBinary: fileNameData,
                            fileTypeBinary: fileType,
                            fileSize: dataCount
                        )
                    )
                }

                _ = try await chat.sendRawMessage(
                    type: type,
                    messageSubtype: messageSubType,
                    text: message,
                    metadata: newMetadata,
                    destructionTimer: destructionTimer,
                    preferredPushType: pushType
                )
            }
        }
#endif
    }
    
    public func sendGroupMessage(message: String) async throws {
        
    }
#endif
    public static func == (lhs: NeedleTailEmitter, rhs: NeedleTailEmitter) -> Bool {
        return lhs.id == rhs.id
    }
}
