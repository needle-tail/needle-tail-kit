//
//  NeedleTailCypherTransport.swift
//
//
//  Created by Cole M on 9/19/21.
//

import CypherMessaging
import Logging
import NeedleTailProtocol
import NeedleTailHelpers
import DequeModule
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import NIOTransportServices
#endif

public class CypherServerTransportClientBridge: CypherServerTransportClient {
    
    internal var configuration: NeedleTailCypherTransport.Configuration
    public init (configuration: NeedleTailCypherTransport.Configuration) {
        self.configuration = configuration
    }
    
    weak var transportBridge: TransportBridge?
    weak var mtDelegate: MessengerTransportBridge?
    
    //MARK: CTK protocol properties
    public var isConnected: Bool = false
    public weak var delegate: CypherTransportClientDelegate?
    /// A **CypherServerTransportClient** property for setting`true` when logged in, `false` on incorrect login, `nil` when no server request has been executed yet
    public internal(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    
    public func setDelegate(to delegate: CypherMessaging.CypherTransportClientDelegate) async throws {
        self.delegate = delegate
        await setTransportDelegate(delegate)
    }
    
    public func reconnect() async throws {
#if os(macOS) || os(iOS)
        guard let messenger = configuration.messenger else { return }
        switch NetworkMonitor.shared.currentStatus {
            case .satisfied:
                try await messenger.resumeService()
            default:
                return
            }
#endif
    }
    
    public func disconnect() async throws {
#if os(macOS) || os(iOS)
        guard let messenger = configuration.messenger else { return }
        switch NetworkMonitor.shared.currentStatus {
            case .satisfied:
                try await messenger.serviceInterupted(true)
            default:
                return
            }
#endif
    }
    
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: CypherProtocol.Username) async throws {
        let bundle = try await readKeyBundle(forUsername: username)
        for validatedBundle in try bundle.readAndValidateDevices() {
            let recipient = NTKUser(username: username, deviceId: validatedBundle.deviceId)
            guard let sender = configuration.username else { return }
            guard let deviceId = configuration.deviceId else { return }
            let receipt = ReadReceipt(
                messageId: remoteId,
                state: .displayed,
                sender:  NTKUser(username: sender, deviceId: deviceId),
                recipient: recipient,
                receivedAt: Date()
            )
            _ = try await transportBridge?.sendReadReceiptMessage(
                recipient: recipient,
                pushType: .none,
                type: .privateMessage,
                readReceipt: receipt
            )
        }
    }
    
    // When a message is received CTK calls this method. We then want to inform the sender we read the message at the correct time.
    public func sendMessageReceivedReceipt(byRemoteId remoteId: String, to username: Username) async throws {
        //If we have the chat view open and we try to process receive messages it doesnt work
        let bundle = try await readKeyBundle(forUsername: username)
        // Get all of the original sender's devices
        for validatedBundle in try bundle.readAndValidateDevices() {
            
            //At this point the recipient(s) are the Sender and it's children devices
            let recipient = NTKUser(username: username, deviceId: validatedBundle.deviceId)
            //At this point the client that this class belongs to becomes the sender
            guard let sender = configuration.username else { return }
            guard let deviceId = configuration.deviceId else { return }
            let receipt = ReadReceipt(
                messageId: remoteId,
                state: .received,
                sender: NTKUser(username: sender, deviceId: deviceId),
                recipient: recipient,
                receivedAt: Date()
            )
            
            //Send to the other users devices(Original Senders) the fact that we have received the message, but have not read it yet
            let result = try await transportBridge?.sendReadReceiptMessage(
                recipient: recipient,
                pushType: .none,
                type: .privateMessage,
                readReceipt: receipt
            )
            
            //Result contains a tuple, a bool value indicating if we received the ACK back and the readReceipt.state(Check if the readReceipt state is set to received; if it is we then can mark it as read). We then add the item to an array of read receipts that need to be marked as displayed. We later use this array of receipts to notify conversation partner that we have read the message if the receiver of the message has readReceipts turned on.
            if let result = result {
                await configuration.readMessagesConsumer.feedConsumer([
                    NeedleTailCypherTransport.MessageToRead(
                        remoteId: remoteId,
                        ntkUser: recipient,
                        deliveryResult: result
                    )
                ])
            }
        }
    }
    
    public func requestDeviceRegistery(_ config: CypherMessaging.UserDeviceConfig) async throws {
        try await transportBridge?.requestDeviceRegistery(config, addChildDevice: configuration.addChildDevice, appleToken: configuration.appleToken ?? "")
    }
    
    public func readKeyBundle(forUsername username: CypherProtocol.Username) async throws -> CypherMessaging.UserConfig {
        guard let transportBridge = transportBridge else { fatalError("Cannot be nil") }
        return try await transportBridge.readKeyBundle(username)
    }
    
    public func publishKeyBundle(_ data: CypherMessaging.UserConfig) async throws {
        try await transportBridge?.publishKeyBundle(data, appleToken: configuration.appleToken ?? "", nameToVerify: configuration.nameToVerify ?? "",recipientDeviceId: configuration.recipientDeviceId)
    }
    
    public func publishBlob<C>(_ blob: C) async throws -> CypherMessaging.ReferencedBlob<C> where C : Decodable, C : Encodable, C : Sendable {
        guard let transportBridge = transportBridge else { throw NeedleTailError.nilBlob }
        return try await transportBridge.publishBlob(blob)
    }
    
    public func readPublishedBlob<C>(byId id: String, as type: C.Type) async throws -> CypherMessaging.ReferencedBlob<C>? where C : Decodable, C : Encodable, C : Sendable {
        fatalError()
    }
    
    public func sendMessage(_ message: CypherProtocol.RatchetedCypherMessage, toUser username: CypherProtocol.Username, otherUserDeviceId: CypherProtocol.DeviceId, pushType: CypherMessaging.PushType, messageId: String) async throws {
        try await self.transportBridge?.sendMessage(
            message: message,
            toUser: username,
            otherUserDeviceId: otherUserDeviceId,
            pushType: pushType,
            messageId: messageId,
            type: configuration.conversationType,
            readReceipt: configuration.readReceipt
        )
    }
    
    public func sendMultiRecipientMessage(_ message: CypherProtocol.MultiRecipientCypherMessage, pushType: CypherMessaging.PushType, messageId: String) async throws {
        fatalError("NeedleTailKit Doesn't support sendMultiRecipientMessage() in this manner")
    }
  
    @NeedleTailClientActor
    internal func setTransportDelegate(_ delegate: CypherTransportClientDelegate) async {
#if os(macOS) || os(iOS)
        guard let messenger = configuration.messenger else { return }
        let plugin = configuration.plugin
        await configuration.client?.delegateJob.addJob(
            NeedleTailCypherTransport.DelegateJob(
                delegate: delegate,
                mtDelegate: mtDelegate,
                plugin: plugin,
                messenger: messenger
            )
        )
#endif
    }
}

@NeedleTailTransportActor
public class NeedleTailCypherTransport: CypherServerTransportClientBridge {
    
    struct DelegateJob {
        var delegate: CypherTransportClientDelegate
        var mtDelegate: MessengerTransportBridge?
        var plugin: NeedleTailPlugin
        var messenger: NeedleTailMessenger
    }
    
    public struct Configuration: Sendable {
        internal var needleTailNick: NeedleTailNick?
        internal var nameToVerify: String?
        internal var keyBundle: String
        internal var recipientDeviceId: DeviceId?
        internal var username: Username?
        internal var deviceId: DeviceId?
        internal var registrationState: RegistrationState
        internal var addChildDevice = false
        internal var client: NeedleTailClient?
        public internal(set) var signer: TransportCreationRequest?
        
        public var supportsDelayedRegistration: Bool
        public var conversationType: ConversationType
        public var appleToken: String?
        public var transportState: TransportState
        public var serverInfo: ClientContext.ServerClientInfo
        public var messenger: NeedleTailMessenger?
        public let plugin: NeedleTailPlugin
        
        internal var messageType = MessageType.message
        internal var readReceipt: ReadReceipt?
        internal var needleTailChannelMetaData: NeedleTailChannelPacket?
        internal var messagesToRead = Deque<MessageToRead>()
        internal var readMessagesConsumer = NeedleTailAsyncConsumer<MessageToRead>()
        
        init(
            needleTailNick: NeedleTailNick? = nil,
            nameToVerify: String? = nil,
            keyBundle: String = "",
            recipientDeviceId: DeviceId? = nil,
            username: Username? = nil,
            deviceId: DeviceId? = nil,
            registrationState: RegistrationState = .full,
            addChildDevice: Bool = false,
            client: NeedleTailClient? = nil,
            signer: TransportCreationRequest? = nil,
            supportsDelayedRegistration: Bool = false,
            conversationType: ConversationType = .privateMessage,
            appleToken: String? = nil,
            transportState: TransportState,
            serverInfo: ClientContext.ServerClientInfo,
            messenger: NeedleTailMessenger? = nil,
            plugin: NeedleTailPlugin,
            messageType: MessageType = MessageType.message,
            readReceipt: ReadReceipt? = nil,
            needleTailChannelMetaData: NeedleTailChannelPacket? = nil,
            messagesToRead: Deque<MessageToRead> = Deque<MessageToRead>(),
            readMessagesConsumer: NeedleTailAsyncConsumer<MessageToRead> = NeedleTailAsyncConsumer<MessageToRead>()
        ) {
            self.needleTailNick = needleTailNick
            self.nameToVerify = nameToVerify
            self.keyBundle = keyBundle
            self.recipientDeviceId = recipientDeviceId
            self.username = username
            self.deviceId = deviceId
            self.registrationState = registrationState
            self.addChildDevice = addChildDevice
            self.client = client
            self.signer = signer
            self.supportsDelayedRegistration = supportsDelayedRegistration
            self.conversationType = conversationType
            self.appleToken = appleToken
            self.transportState = transportState
            self.serverInfo = serverInfo
            self.messenger = messenger
            self.plugin = plugin
            self.messageType = messageType
            self.readReceipt = readReceipt
            self.needleTailChannelMetaData = needleTailChannelMetaData
            self.messagesToRead = messagesToRead
            self.readMessagesConsumer = readMessagesConsumer
        }
    }
    
    struct MessageToRead: Sendable {
        var remoteId: String
        var ntkUser: NTKUser
        var deliveryResult: (Bool, ReadReceipt.State)
    }
    
    private let logger = Logger(label: "IRCMessenger - ")
    
    override public init(
        configuration: Configuration
    )  {
        super.init(configuration: configuration)
        self.configuration = configuration
    }
    
    enum ClientServerState {
        case clientRegistering, lockState
    }
    
#if os(macOS) || os(iOS)
    public class func authenticate(
        appleToken: String? = "",
        transportRequest: TransportCreationRequest?,
        serverInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin,
        messenger: NeedleTailMessenger
    ) -> NeedleTailCypherTransport {
        return NeedleTailCypherTransport(
            configuration:
                Configuration(
                    username: transportRequest?.username,
                    deviceId: transportRequest?.deviceId,
                    signer: transportRequest,
                    appleToken: appleToken,
                    transportState: TransportState(
                        identifier: UUID(),
                        messenger: messenger
                    ),
                    serverInfo: serverInfo,
                    messenger: messenger,
                    plugin: plugin
                )
        )
    }
#endif
    
    func createClient(_
                      nameToVerify: String? = nil,
                      newHost: String = "",
                      tls: Bool = true
    ) async throws {
        if !newHost.isEmpty {
            configuration.serverInfo = ClientContext.ServerClientInfo(hostname: newHost, tls: tls)
        }
        var deviceId: DeviceId?
        
        if configuration.signer?.username.raw == nil {
            //We are checking if we have an account
            configuration.nameToVerify = nameToVerify?.replacingOccurrences(of: " ", with: "").ircLowercased()
        } else {
            //We have an account
            configuration.nameToVerify = configuration.signer?.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
        }
        
        if configuration.signer?.deviceId == nil {
            deviceId = DeviceId("")
        } else {
            deviceId = configuration.signer?.deviceId
        }
        guard let name = configuration.nameToVerify else { throw NeedleTailError.nilNickName }
        configuration.needleTailNick = NeedleTailNick(name: name, deviceId: deviceId)
        guard let nick = configuration.needleTailNick else { throw NeedleTailError.nilNickName }
        
        let clientContext = ClientContext(
            serverInfo: configuration.serverInfo,
            nickname: nick
        )
        guard let deviceId = deviceId else { throw NeedleTailError.deviceIdNil }
#if os(macOS) || os(iOS)
        let username = Username(name)
        guard let messenger = configuration.messenger else { return }
        let cypher = await messenger.cypher
        let client = NeedleTailClient(
            ntkBundle: NTKClientBundle(
                signer: configuration.signer,
                cypher: cypher,
                cypherTransport: self
            ),
            transportState: configuration.transportState,
            clientContext: clientContext,
            ntkUser: NTKUser(
                username: username,
                deviceId: deviceId
            ),
            messenger: messenger
        )

        configuration.client = client
        self.transportBridge = client

        try await self.transportBridge?.connectClient(
            serverInfo: client.serverInfo,
            groupManager: client.groupManager,
            ntkBundle: client.ntkBundle,
            transportState: client.transportState,
            clientContext: client.clientContext,
            messenger: client.messenger
        )
        try await self.transportBridge?.resumeClient(
            type: configuration.appleToken != "" ? .siwa(configuration.appleToken!) : .plain(name),
            state: configuration.registrationState
        )
#endif
    }
    
    struct SignUpResponse: Codable {
        let existingUser: Username?
    }
    
}

public enum RegistrationType: Sendable {
    case siwa(String), plain(String)
}

public enum RegistrationState: Sendable {
    case full, temp
}


extension NeedleTailCypherTransport {
    
    @MainActor
    func updateEmitter(_ data: Data?) async {
#if (os(macOS) || os(iOS))
        guard let messenger = configuration.messenger else { return }
        messenger.emitter.showScanner = true
        /// Send **User Config** data to generate a QRCode in the **Child Device**
        messenger.emitter.requestMessageId = nil
        messenger.emitter.qrCodeData = data
#endif
    }
    
    public struct SetToken: Codable {
        let token: String
    }
    
    /// This method has 2 purposes.
    /// - **1 create new channel locally and the send the metadata to the server in order to join the channel**
    /// - **2. If a locally channel already exists, there is no need to create it again so we just join the channel.**
    /// - Parameters:
    ///   - name: Name of the channel
    ///   - admin: Admin's Username i.e. **needletail:123-456-234-sdga34-vadf**
    ///   - organizers: Set of the organizers on this channel
    ///   - members:Set of the members on this channel
    ///   - permissions: The channel permission
    func createLocalChannel(
        name: String,
        admin: Username,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) async throws {
        
        guard members.count > 1 else { throw NeedleTailError.membersCountInsufficient }
        
        let seperated = admin.description.components(separatedBy: ":")
        guard let needleTailAdmin = NeedleTailNick(name: seperated[0], deviceId: DeviceId(seperated[1])) else { return }
        
        //Build our server message, we set the meta data variable here, this will give sendMessage the needed data by the time the sendMessage flow starts.
        configuration.needleTailChannelMetaData = NeedleTailChannelPacket(
            name: name,
            admin: needleTailAdmin,
            organizers: organizers,
            members: members,
            permissions: permissions
        )
        
        var cypher: CypherMessenger?
#if os(macOS) || os(iOS)
        cypher = await configuration.messenger?.cypher
#endif
        let metaDoc = try BSONEncoder().encode(configuration.needleTailChannelMetaData)
        
        guard let cypher = cypher else { return }
        
        //Always remove Admin, CTK will add it layer. We need it pass through though for NTK MetaData
        var members = members
        members.remove(admin)
        var organizers = organizers
        organizers.remove(admin)
        switch try await searchChannels(cypher, channelName: name) {
        case .new:
            /// This will kick off a sendMessage flow. Everytime `createGroupChat(with:)` is called we initialized a new conversation with a  new *UUID*.
            /// That means we need a way of checking if the conversation already exist before we create a new one, if not we will create multiple local channels with the same name.
            /// CTK will add the current user as a member and moderator/organizer. This is fine, but we are Identifeing a device paried with it's username.
            /// So we want to add the **NeedTailNick** which contains the Identifier. This will end up placing the CTK Username and our NTNick in the Set of members&moderators.
            /// Technically these are duplicates and unnecessary. We want to keep our metadata with the needed info for the server and at the same time strip what is unneeded for CTK.
            /// If we don't not only will we have duplicates but, when CTK calls `readKeyBundle` it will try and read the NTNick which the serve doesn't know about the
            /// Device Identity for a key bundle; therefore it will throw an error saying that we cannot fond the key bundle. It is best to just remove the duplicate to avoid all these problems.
            let group = try await cypher.createGroupChat(with: members, localMetadata: metaDoc, sharedMetadata: metaDoc)
            await updateGroupChats(group, organizers: organizers, members: members, meta: metaDoc)
        case .found(let chat):
            /// We already have a chat... So just update localDB
            await updateGroupChats(chat, organizers: organizers, members: members, meta: metaDoc)
        default:
            break
        }
        /// Send the Channel Info to NeedleTailServer
        let meta = try BSONDecoder().decode(NeedleTailChannelPacket.self, from: metaDoc)
        
        try await transportBridge?.createNeedleTailChannel(
            name: meta.name,
            admin: meta.admin,
            organizers: meta.organizers,
            members: meta.members,
            permissions: meta.permissions
        )
    }
    
    enum SearchResult {
        case new, found(GroupChat), none
    }
    
    ///We want to first make sure that a channel doesn't exist with the and ID
    @NeedleTailTransportActor
    func searchChannels(_ cypher: CypherMessenger, channelName: String) async throws -> SearchResult {
#if (os(macOS) || os(iOS))
        guard let messenger = configuration.messenger else { return .none }
        _ = await messenger.fetchChats(cypher: cypher)
        let groupChats = try await messenger.fetchGroupChats(cypher)
        let channel = try await groupChats.asyncFirstThrowing { chat in
            let metaDoc = await chat.conversation.metadata
            let meta = try BSONDecoder().decode(GroupMetadata.self, from: metaDoc)
            let config = try BSONDecoder().decode(NeedleTailChannelPacket.self, from: meta.config.blob.metadata)
            return config.name == channelName
        }
        
        guard let channel = channel else { return .new }
        return .found(channel)
#else
        return .none
#endif
    }
    
    @NeedleTailTransportActor
    func updateGroupChats(_
                          group: GroupChat,
                          organizers: Set<Username>,
                          members: Set<Username>,
                          meta: Document
    ) async {
        //Update any organizers Locally
        var config = await group.getGroupConfig()
        for organizer in organizers {
            if config.blob.moderators.contains(organizer) == false {
                config.blob.promoteAdmin(organizer)
            }
        }
        
        //Update localDB with members
        for member in members {
            guard !config.blob.members.contains(member) else { return }
            config.blob.addMember(member)
        }
        
        config.blob.metadata = meta
    }    
    fileprivate struct MultipartQueuedPacket: Sendable {
        var packet: MultipartMessagePacket
        var message: RatchetedCypherMessage
        var deviceId: DeviceId
        var username: String
    }
    
    internal func sendMessageReadReceipt() async throws {
        for try await result in NeedleTailAsyncSequence<MessageToRead>(consumer: configuration.readMessagesConsumer) {
            switch result {
            case .success(let message):
                //Only read if the message is in view
#if (os(macOS) || os(iOS))
                guard let messenger = configuration.messenger else { return }
                if await messenger.emitter.readReceipts == true {
                    if message.deliveryResult.0 == true && message.deliveryResult.1 == .received {
                        //Send to the message sender sender,
                        let recipient = NTKUser(username: message.ntkUser.username, deviceId: message.ntkUser.deviceId)
                        guard let sender = configuration.username else { return }
                        guard let deviceId = configuration.deviceId else { return }
                        let receipt = ReadReceipt(
                            messageId: message.remoteId,
                            state: .displayed,
                            sender:  NTKUser(username: sender, deviceId: deviceId),
                            recipient: recipient,
                            receivedAt: Date()
                        )
                        _ = try await transportBridge?.sendReadReceiptMessage(
                            recipient: recipient,
                            pushType: .none,
                            type: .privateMessage,
                            readReceipt: receipt
                        )
                    }
                }
#else
                return
#endif
            default:
                return
            }
        }
    }
    
    public func sendReadMessages(count: Int) async throws {
        try await transportBridge?.sendReadMessages(count: count)
    }
    
    @MultipartActor
    public func downloadMultipart(_ metadata: [String]) async throws {
        try await transportBridge?.downloadMultipart(metadata)
    }
    
    @MultipartActor
    public func uploadMultipart(_ multipartPacket: MultipartMessagePacket) async throws {
        try await transportBridge?.uploadMultipart(multipartPacket)
    }
    
    //    public func sendMultiRecipientMessage(_ message: MultiRecipientCypherMessage, pushType: PushType, messageId: String) async throws {
    //        fatalError("NeedleTailKit Doesn't support sendMultiRecipientMessage() in this manner")
    //    }
}

protocol IRCMessageDelegate {
    func passSendMessage(_ text: Data, to recipients: IRCMessageRecipient, tags: [IRCTags]?) async
}


let charA = UInt8(UnicodeScalar("a").value)
let char0 = UInt8(UnicodeScalar("0").value)

private func itoh(_ value: UInt8) -> UInt8 {
    return (value > 9) ? (charA + value - 10) : (char0 + value)
}

extension DataProtocol {
    var hexString: String {
        var bytes = [UInt8]()
        
        self.regions.forEach { (_) in
            for i in self {
                bytes.append(itoh((i >> 4) & 0xF))
                bytes.append(itoh(i & 0xF))
            }
        }
        
        return String(bytes: bytes, encoding: .utf8)!
    }
}

extension URLResponse {
    convenience public init?(_ url: URL) {
        self.init(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: "")
    }
}

extension Array {
    func asyncFirstThrowing(where matches: (Element) async throws -> Bool) async rethrows -> Element? {
        for i in 0..<self.count {
            let element = self[i]
            if try await matches(element) {
                return element
            }
        }
        return nil
    }
}

@globalActor actor TransportStoreActor {
    static var shared = TransportStoreActor()
    internal init() {}
}

final class TransportStore {
    @KeyBundleMechanismActor
    var keyBundle: UserConfig?
    var acknowledgment: Acknowledgment.AckType = .none
    var setAcknowledgement: Acknowledgment.AckType = .none {
        didSet {
            acknowledgment = setAcknowledgement
        }
    }
    
    func setAck(_ ack: Acknowledgment.AckType) {
        acknowledgment = ack
        Logger(label: "Transport Store").info("INFO RECEIVED - ACK: - \(acknowledgment)")
    }
    
    @KeyBundleMechanismActor
    func setKeyBundle(_ config: UserConfig) {
        keyBundle = config
    }
}
