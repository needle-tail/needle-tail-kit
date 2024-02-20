//
//  NeedleTailCypherTransport.swift
//
//
//  Created by Cole M on 9/19/21.
//

@preconcurrency import CypherMessaging
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
    var mtDelegate: MessengerTransportBridge?
    
    //MARK: CTK protocol properties
    public var isConnected: Bool = false
    public weak var delegate: CypherTransportClientDelegate?
    /// A **CypherServerTransportClient** property for setting`true` when logged in, `false` on incorrect login, `nil` when no server request has been executed yet
    public internal(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    
    public func setDelegate(to delegate: CypherMessaging.CypherTransportClientDelegate) async throws {
        self.delegate = delegate
    }
    
    public func reconnect() async throws {
#if os(macOS) || os(iOS)
        switch await NetworkMonitor.shared.status {
        case .satisfied:
            if await NeedleTailEmitter.shared.connectionState != .registered {
                try await configuration.messenger.resumeService()
            }
        default:
            return
        }
#endif
    }
    
    public func disconnect() async throws {
#if os(macOS) || os(iOS)
        switch await NetworkMonitor.shared.status {
        case .satisfied:
            try await configuration.messenger.serviceInterupted(true)
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
                await setCanSendReadReceipt(!configuration.readMessagesConsumer.deque.isEmpty)
            }
        }
    }
    
    @MainActor
    internal func setCanSendReadReceipt(_ canRead: Bool) {
#if (os(macOS) || os(iOS))
        configuration.messenger.emitter.canSendReadReceipt = canRead
#endif
    }
    
    public func requestDeviceRegistery(_ config: CypherMessaging.UserDeviceConfig) async throws {
        try await transportBridge?.requestDeviceRegistery(config, addChildDevice: configuration.addChildDevice, appleToken: configuration.appleToken ?? "")
    }
    
    public func readKeyBundle(forUsername username: CypherProtocol.Username) async throws -> CypherMessaging.UserConfig {
        guard let transportBridge = transportBridge else { throw NeedleTailError.transportBridgeDelegateNotSet }
        return try await transportBridge.readKeyBundle(username)
    }
    
    public func publishKeyBundle(_ data: CypherMessaging.UserConfig) async throws {
        try await transportBridge?.publishKeyBundle(data, appleToken: configuration.appleToken ?? "", nameToVerify: configuration.nameToVerify ?? "",recipientDeviceId: configuration.recipientDeviceId)
    }
    
    public func publishBlob<C>(_ blob: C) async throws -> CypherMessaging.ReferencedBlob<C> where C : Decodable, C : Encodable, C : Sendable {
        guard let transportBridge = transportBridge else { throw NeedleTailError.transportBridgeDelegateNotSet }
        return try await transportBridge.publishBlob(blob)
    }
    
    public func readPublishedBlob<C>(byId id: String, as type: C.Type) async throws -> CypherMessaging.ReferencedBlob<C>? where C : Decodable, C : Encodable, C : Sendable {
        fatalError("NeedleTailKit Doesn't support readPublishedBlob() in this manner")
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
}

public class NeedleTailCypherTransport: CypherServerTransportClientBridge {

    public struct Configuration: Sendable {
        internal var needleTailNick: NeedleTailNick? = nil
        internal var nameToVerify: String? = nil
        internal var keyBundle: String = ""
        internal var recipientDeviceId: DeviceId? = nil
        internal var username: Username? = nil
        internal var deviceId: DeviceId? = nil
        internal var registrationState: RegistrationState = .full
        internal var addChildDevice = false
        internal var client: NeedleTailClient? = nil
        public internal(set) var signer: TransportCreationRequest? = nil
        
        public var supportsDelayedRegistration: Bool = false
        public var conversationType: ConversationType = .privateMessage
        public var appleToken: String? = nil
        public var transportState: TransportState
        public var serverInfo: ClientContext.ServerClientInfo
        public var messenger: NeedleTailMessenger
        public let plugin: NeedleTailPlugin
        
        internal var messageType = MessageType.message
        internal var readReceipt: ReadReceipt? = nil
        internal var needleTailChannelMetaData: NeedleTailChannelPacket? = nil
        internal var messagesToRead = Deque<MessageToRead>()
        internal var readMessagesConsumer = NeedleTailAsyncConsumer<MessageToRead>()
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
    
    public struct ClientInfo: Sendable {
        var clientContext: ClientContext
        var username: Username
        var deviceId: DeviceId
    }
    
    func setUpClientInfo(
        nameToVerify: String? = nil,
        newHost: String = "",
        tls: Bool = true
    ) async throws -> ClientInfo {
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
        let username = Username(name)
        return ClientInfo(
            clientContext: clientContext,
            username: username,
            deviceId: deviceId
        )
    }
    
    func createClient(_
                      cypherTransport: NeedleTailCypherTransport,
                      clientInfo: ClientInfo
    ) async throws {
#if os(macOS) || os(iOS)
        let cypher = await configuration.messenger.cypher
        let client = NeedleTailClient(
            configuration: NeedleTailClient.Configuration(
                ntkBundle:  NTKClientBundle(
                    signer: configuration.signer,
                    cypher: cypher,
                    cypherTransport: self
                ),
                transportState: configuration.transportState,
                clientContext: clientInfo.clientContext,
                serverInfo: clientInfo.clientContext.serverInfo,
                ntkUser: NTKUser(
                    username: clientInfo.username,
                    deviceId: clientInfo.deviceId
                ),
                messenger: configuration.messenger
            )
        )
        
        configuration.client = client
        self.transportBridge = client
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            try Task.checkCancellation()
            
            //Create Channel
            let transportState = await client.configuration.transportState
            let serverInfo = await client.configuration.serverInfo
            switch await transportState.current {
            case .clientOffline, .transportOffline:
                await transportState.transition(to: .clientConnecting)
                
                let childChannel = try await client.createChannel(
                    host: serverInfo.hostname,
                    port: serverInfo.port,
                    enableTLS: serverInfo.tls,
                    groupManager: client.groupManager,
                    group: client.groupManager.groupWrapper.group
                )
                await client.setChildChannel(childChannel)
                let store = TransportStore()
                try await client.setStore(store)

                await transportState.transition(to: .clientConnected)
                
                // Create long running task to handle streams of data
                group.addTask {
                    try await self.transportBridge?.processStream(
                        childChannel: childChannel,
                        store: store
                    )
                }
            default:
                throw NeedleTailError.couldNotConnectToNetwork
            }
        }
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
        configuration.messenger.emitter.showScanner = true
        /// Send **User Config** data to generate a QRCode in the **Child Device**
        configuration.messenger.emitter.requestMessageId = nil
        configuration.messenger.emitter.qrCodeData = data
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
        cypher = await configuration.messenger.cypher
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
    func searchChannels(_ cypher: CypherMessenger, channelName: String) async throws -> SearchResult {
#if (os(macOS) || os(iOS))
        try await configuration.messenger.loadContactBundle(cypher: cypher)
        let groupChats = try await configuration.messenger.fetchGroupChats(cypher)
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
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self else { return }
            for try await result in NeedleTailAsyncSequence<MessageToRead>(consumer: self.configuration.readMessagesConsumer) {
                try Task.checkCancellation()
                group.addTask { [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let message):
                        //Only read if the message is in view
#if (os(macOS) || os(iOS))
                        if await configuration.messenger.emitter.isReadReceiptsOn == true {
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
                                return
                            }
                        } else {
                            return
                        }
#else
                        return
#endif
                    case .consumed:
                        return
                    }
                }
                _ = try await group.next()
                group.cancelAll()
            }
        }
        await setCanSendReadReceipt(!configuration.readMessagesConsumer.deque.isEmpty)
    }
    
    public func sendReadMessages(count: Int) async throws {
        try await transportBridge?.sendReadMessages(count: count)
    }
    
    func sendTyping(status: TypingStatus, nick: NeedleTailNick) async throws {
        try await transportBridge?.sendTyping(status, nick: nick)
    }
    
    @MultipartActor
    public func downloadMultipart(_ metadata: [String]) async throws {
        try await transportBridge?.downloadMultipart(metadata)
    }
    
    @MultipartActor
    public func uploadMultipart(_ multipartPacket: MultipartMessagePacket) async throws {
        try await transportBridge?.uploadMultipart(multipartPacket)
    }
    
    @MultipartActor
    public func requestBucketContents(_ bucket: String) async throws {
        try await transportBridge?.requestBucketContents(bucket)
    }
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

actor TransportStore {
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
    
    func setKeyBundle(_ config: UserConfig) {
        keyBundle = config
    }
    
    func clearUserConfig() {
        keyBundle = nil
    }
}
