//
//  NeedleTailMessenger.swift
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


public class NeedleTailMessenger: CypherServerTransportClient, @unchecked Sendable {
    
    
    public var isConnected: Bool = false
    public var supportsDelayedRegistration = false
    public weak var delegate: CypherTransportClientDelegate?
    /// A **CypherServerTransportClient** property for setting`true` when logged in, `false` on incorrect login, `nil` when no server request has been executed yet
    public internal(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    public var type: ConversationType = .privateMessage
    public private(set) var signer: TransportCreationRequest?
    private(set) var needleTailNick: NeedleTailNick?
    private let appleToken: String?
    private var nameToVerify: String?
    private var transportState: TransportState
    private var serverInfo: ClientContext.ServerClientInfo
    private var keyBundle: String = ""
    var recipientDeviceId: DeviceId?
    var emitter: NeedleTailEmitter?
    @MainActor
    var plugin: NeedleTailPlugin
    var logger: Logger
    var messageType = MessageType.message
    var multipartMessagePacket: MultipartMessagePacket?
    var lastMultipartMessagePacket: MultipartMessagePacket?
    fileprivate var multipartMessagesConsumer = NeedleTailAsyncConsumer<MultipartQueuedPacket>()
    
    var readReceipt: ReadReceipt?
    var needleTailChannelMetaData: NeedleTailChannelPacket?
    var username: Username?
    var deviceId: DeviceId?
    var registrationState: RegistrationState = .full
    var addChildDevice = false
    var client: NeedleTailClient? {
        didSet {
            Task {
                if let delegate = delegate {
                    await setTransportDelegate(delegate)
                }
            }
        }
    }
    weak var transportBridge: TransportBridge?
    @NeedleTailTransportActor
    weak var mtDelegate: MessengerTransportBridge?
    
    struct MessageToRead: Sendable {
        var remoteId: String
        var ntkUser: NTKUser
        var deliveryResult: (Bool, ReadReceipt.State)
    }
    var messagesToRead = Deque<MessageToRead>()
    var readMessagesConsumer = NeedleTailAsyncConsumer<MessageToRead>()
    
    @NeedleTailTransportActor
    public init(
        username: Username? = nil,
        deviceId: DeviceId? = nil,
        signer: TransportCreationRequest? = nil,
        appleToken: String? = nil,
        transportState: TransportState,
        serverInfo: ClientContext.ServerClientInfo,
        emitter: NeedleTailEmitter,
        plugin: NeedleTailPlugin
    ) async throws {
        self.logger = Logger(label: "IRCMessenger - ")
        self.transportState = transportState
        self.serverInfo = serverInfo
        self.username = username
        self.deviceId = deviceId
        self.signer = signer
        self.appleToken = appleToken
        self.emitter = emitter
        self.plugin = plugin
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
        emitter: NeedleTailEmitter
    ) async throws -> NeedleTailMessenger {
        return try await NeedleTailMessenger(
            username: transportRequest?.username,
            deviceId: transportRequest?.deviceId,
            signer: transportRequest,
            appleToken: appleToken,
            transportState: TransportState(
                identifier: UUID(),
                emitter: emitter
            ),
            serverInfo: serverInfo,
            emitter: emitter,
            plugin: plugin
        )
    }
#endif
    
    func createClient(_
                      nameToVerify: String? = nil,
                      newHost: String = "",
                      tls: Bool = true
    ) async throws {
        if !newHost.isEmpty {
            self.serverInfo = ClientContext.ServerClientInfo(hostname: newHost, tls: tls)
        }
        var deviceId: DeviceId?
        
        if signer?.username.raw == nil {
            //We are checking if we have an account
            self.nameToVerify = nameToVerify?.replacingOccurrences(of: " ", with: "").ircLowercased()
        } else {
            //We have an account
            self.nameToVerify = signer?.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
        }
        
        if signer?.deviceId == nil {
            deviceId = DeviceId("")
        } else {
            deviceId = signer?.deviceId
        }
        guard let name = self.nameToVerify else { throw NeedleTailError.nilNickName }
        self.needleTailNick = NeedleTailNick(name: name, deviceId: deviceId)
        guard let nick = self.needleTailNick else { throw NeedleTailError.nilNickName }
        
        let clientContext = ClientContext(
            serverInfo: self.serverInfo,
            nickname: nick
        )
        guard let deviceId = deviceId else { throw NeedleTailError.deviceIdNil }
#if os(macOS) || os(iOS)
        let username = Username(name)
        let client = await NeedleTailClient(
            ntkBundle: NTKClientBundle(
                cypher: emitter?.cypher,
                messenger: self,
                signer: signer
            ),
            transportState: self.transportState,
            clientContext: clientContext,
            ntkUser: NTKUser(
                username: username,
                deviceId: deviceId
            )
        )
        
        self.transportBridge = client
        try await self.transportBridge?.connectClient()
        try await self.transportBridge?.resumeClient(
            type: self.appleToken != "" ? .siwa(self.appleToken!) : .plain(name),
            state: self.registrationState
        )
        self.client = client
#endif
    }
    
    //MARK: Delegate setters
    public func setDelegate(to delegate: CypherTransportClientDelegate) async throws {
        self.delegate = delegate
        await setTransportDelegate(delegate)
    }
    
    @NeedleTailClientActor
    private func setTransportDelegate(_ delegate: CypherTransportClientDelegate) async {
#if os(macOS) || os(iOS)
        guard let emitter = emitter else { return }
        await client?.setDelegates(
            delegate,
            mtDelegate: mtDelegate,
            plugin: plugin,
            emitter: emitter
        )
#endif
    }
    
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    public func publishKeyBundle(_ data: UserConfig) async throws {
        try await transportBridge?.publishKeyBundle(data, appleToken: appleToken ?? "", nameToVerify: nameToVerify ?? "",recipientDeviceId: recipientDeviceId)
    }
    
    
    
    /// When we initially create a user we need to read the key bundle upon registration. Since the User is created on the Server a **UserConfig** exists.
    /// Therefore **CypherTextKit** will ask to read that users bundle. If It does not exist then the error is caught and we will call ``publishKeyBundle(_ data:)``
    /// from **CypherTextKit**'s **registerMessenger()** method.
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        guard let transportBridge = transportBridge else { throw NeedleTailError.bridgeDelegateNotSet }
        return try await transportBridge.readKeyBundle(username)
    }
    
    struct SignUpResponse: Codable {
        let existingUser: Username?
    }
    
}

public enum RegistrationType {
    case siwa(String), plain(String)
}

public enum RegistrationState {
    case full, temp
}


extension NeedleTailMessenger {
    
    public func reconnect() async throws {
#if os(macOS) || os(iOS)
        let newStatus = await NeedleTail.shared.state.receiver.statusArray
        for status in newStatus {
            switch status {
            case .satisfied:
                try await NeedleTail.shared.resumeService()
            default:
                return
            }
        }
#endif
    }
    
    public func disconnect() async throws {
#if os(macOS) || os(iOS)
        let newStatus = await NeedleTail.shared.state.receiver.statusArray
        for status in newStatus {
            switch status {
            case .satisfied:
                try await NeedleTail.shared.serviceInterupted(true)
            default:
                return
            }
        }
#endif
    }
    
    /// When we request a new device registration. We generate a QRCode that the master device needs to scan. Once that is scanned, the master device should notify via a server request/response to the child in order to set masterScanned to true. The the new device can register to IRC and receive messages with that username.
    /// - Parameter config: The Requesters User Device Configuration
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {
        try await transportBridge?.requestDeviceRegistery(config, addChildDevice: addChildDevice, appleToken: appleToken ?? "")
    }
    
    @MainActor
    func updateEmitter(_ data: Data?) {
#if (os(macOS) || os(iOS))
        guard let emitter = emitter else { return }
        emitter.showScanner = true
        /// Send **User Config** data to generate a QRCode in the **Child Device**
        emitter.requestMessageId = nil
        emitter.qrCodeData = data
#endif
    }
    
    public struct SetToken: Codable {
        let token: String
    }
    
    @BlobActor
    public func publishBlob<C>(_ blob: C) async throws -> ReferencedBlob<C> where C : Decodable, C : Encodable {
        guard let transportBridge = transportBridge else { throw NeedleTailError.nilBlob }
        return try await transportBridge.publishBlob(blob)
    }
    
    @NeedleTailTransportActor
    public func readPublishedBlob<C>(byId id: String, as type: C.Type) async throws -> ReferencedBlob<C>? where C : Decodable, C : Encodable {
        fatalError()
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
    @NeedleTailTransportActor
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
        needleTailChannelMetaData = NeedleTailChannelPacket(
            name: name,
            admin: needleTailAdmin,
            organizers: organizers,
            members: members,
            permissions: permissions
        )
        
        var cypher: CypherMessenger?
#if os(macOS) || os(iOS)
        cypher = emitter?.cypher
#endif
        let metaDoc = try BSONEncoder().encode(needleTailChannelMetaData)
        
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
        guard let emitter = emitter else { return .none }
        _ = await emitter.fetchChats(cypher: cypher)
        let groupChats = try await emitter.fetchGroupChats(cypher)
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
    
    func configureMultipartMessagePacket(_
                                         multipartMessagePacket: MultipartMessagePacket,
                                         username: String,
                                         deviceId: DeviceId
    ) async -> MultipartMessagePacket {
        var multipartMessagePacket = multipartMessagePacket
        multipartMessagePacket.recipient = NeedleTailNick(name: username, deviceId: deviceId)
        multipartMessagePacket.fileName = multipartMessagePacket.fileName + "_\(deviceId.description)"
        return multipartMessagePacket
        
    }
    
    fileprivate struct MultipartQueuedPacket: Sendable {
        var packet: MultipartMessagePacket
        var message: RatchetedCypherMessage
        var deviceId: DeviceId
        var username: String
    }
    
    /// We are getting the message from CypherTextKit after Encryption. Our Client will send it to CypherTextKit Via `sendRawMessage()`. This method will also send the message to all parties involved the target destination and all user devices from the sender.
    public func sendMessage(_
                            message: RatchetedCypherMessage,
                            toUser username: Username,
                            otherUserDeviceId deviceId: DeviceId,
                            pushType: PushType,
                            messageId: String
    ) async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            
            if let multipartMessagePacket = multipartMessagePacket {
                group.addTask { [weak self] in
                    guard let self else { return }
                    //Queue MultipartPacket sending in case multiple packets are being tried to send
                    await self.multipartMessagesConsumer.feedConsumer([
                        MultipartQueuedPacket(
                            packet: multipartMessagePacket,
                            message: message,
                            deviceId: deviceId,
                            username: username.raw
                        )
                    ])
                    
                    
                    for try await result in NeedleTailAsyncSequence(consumer: self.multipartMessagesConsumer) {
                        switch result {
                        case .success(let queuedPacket):
                            let packet = await self.configureMultipartMessagePacket(
                                queuedPacket.packet,
                                username: queuedPacket.username,
                                deviceId: queuedPacket.deviceId
                            )
                            //We only want to send this to one user, if we have multiple device it will send it that many times to the server because CTK is handling multiple user support. This is probably why I am failing to decrypt the packets also, because it may being using the wrong keys per device. Ideally we want to send this information once to prevent overhead, but we also want to send both the signing info for the packet. I dont think this can be done correctly. we do need to sign each packet accordingly, which means we would need to store 1 packet per device since 1 packet is encrypted per device keys. This could use a lot of space of Mongo if users are never downloading the image so we can delete it on mongo. Typically user do download though. In order to do what we want we need to name the packets differently(i.e. mediaId_1_8_deviceId)
                            try await self.transportBridge?.uploadMultipart(packet, message: queuedPacket.message)
                        default:
                            return
                        }
                    }
                }
            } else {
                group.addTask { [weak self] in
                    guard let self else { return }
                    try await self.transportBridge?.sendMessage(
                        message: message,
                        toUser: username,
                        otherUserDeviceId: deviceId,
                        pushType: pushType,
                        messageId: messageId,
                        type: self.type,
                        readReceipt: self.readReceipt
                    )
                }
            }
        }
    }
    
    //Should be done by Recipient
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: Username) async throws {
        let bundle = try await readKeyBundle(forUsername: username)
        for validatedBundle in try bundle.readAndValidateDevices() {
            let recipient = NTKUser(username: username, deviceId: validatedBundle.deviceId)
            guard let sender = self.username else { return }
            guard let deviceId = self.deviceId else { return }
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
            guard let sender = self.username else { return }
            guard let deviceId = self.deviceId else { return }
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
                await self.readMessagesConsumer.feedConsumer([
                    MessageToRead(
                        remoteId: remoteId,
                        ntkUser: recipient,
                        deliveryResult: result
                    )
                ])
            }
        }
    }
    
    internal func sendMessageReadReceipt() async throws {
        for try await result in NeedleTailAsyncSequence<MessageToRead>(consumer: readMessagesConsumer) {
            switch result {
            case .success(let message):
                //Only read if the message is in view
#if (os(macOS) || os(iOS))
                if emitter?.readReceipts == true {
                    if message.deliveryResult.0 == true && message.deliveryResult.1 == .received {
                        //Send to the message sender sender,
                        let recipient = NTKUser(username: message.ntkUser.username, deviceId: message.ntkUser.deviceId)
                        guard let sender = self.username else { return }
                        guard let deviceId = self.deviceId else { return }
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
    public func listFilenames(_ metadata: [String]) async throws {
        try await transportBridge?.listFilenames(metadata)
    }
    
    public func sendMultiRecipientMessage(_ message: MultiRecipientCypherMessage, pushType: PushType, messageId: String) async throws {
        fatalError("NeedleTailKit Doesn't support sendMultiRecipientMessage() in this manner")
    }
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
}
