//
//  NeedleTailMessenger.swift
//
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIOCore
import NIOPosix
import CypherMessaging
import CypherProtocol
import MessagingHelpers
import Crypto
import BSON
import JWTKit
import Logging
import NeedleTailProtocol
import NeedleTailHelpers
//import AsyncAlgorithms
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import NIOTransportServices
#endif

public class NeedleTailMessenger: CypherServerTransportClient {
    public var isConnected: Bool = false
    public var supportsDelayedRegistration = false
    public weak var delegate: CypherTransportClientDelegate?
    public internal(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    public var type : ConversationType = .privateMessage
    public private(set) var signer: TransportCreationRequest?
    private(set) var needleTailNick: NeedleTailNick?
    private let appleToken: String?
    private var transportState: TransportState
    private var clientInfo: ClientContext.ServerClientInfo
    private var keyBundle: String = ""
    var recipientDeviceId: DeviceId?
    var cypher: CypherMessenger?
    var client: NeedleTailClient?
    var plugin: NeedleTailPlugin
    var logger: Logger
    var messageType = MessageType.message
    var readReceipt: ReadReceipt?
    var needleTailChannelMetaData: NeedleTailChannelPacket?
    let username: Username?
    let deviceId: DeviceId?
    var registrationState: RegistrationState = .full
    
    @NeedleTailTransportActor
    public init(
        username: Username?,
        deviceId: DeviceId?,
        signer: TransportCreationRequest?,
        appleToken: String?,
        transportState: TransportState,
        clientInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin
    ) async throws {
        self.logger = Logger(label: "IRCMessenger - ")
        self.transportState = transportState
        self.clientInfo = clientInfo
        self.username = username
        self.deviceId = deviceId
        self.signer = signer
        self.appleToken = appleToken
        self.plugin = plugin
    }
    
    enum ClientServerState {
        case clientRegistering, lockState
    }
    
    
    @NeedleTailClientActor
    public class func authenticate(
        appleToken: String? = "",
        transportRequest: TransportCreationRequest?,
        clientInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin
    ) async throws -> NeedleTailMessenger {
        return try await NeedleTailMessenger(
            username: transportRequest?.username,
            deviceId: transportRequest?.deviceId,
            signer: transportRequest,
            appleToken: appleToken,
            transportState: TransportState(identifier: UUID(), emitter: plugin.emitter),
            clientInfo: clientInfo,
            plugin: plugin
        )
    }
    
    @NeedleTailClientActor
    public func registrationType(_ appleToken: String = "") -> RegistrationType {
        if !appleToken.isEmpty {
            return .siwa(appleToken)
        } else {
            return .plain
        }
    }
    
    @NeedleTailClientActor
    func startSession(_
                      client: NeedleTailClient,
                      type: RegistrationType,
                      nameToVerify: String? = nil,
                      state: RegistrationState? = .full
    ) async throws {
        switch type {
        case .siwa(let apple):
            try await self.registerSession(client, appleToken: apple)
        case .plain:
            try await self.registerSession(client, nameToVerify: nameToVerify, state: state)
        }
    }
    
    @NeedleTailClientActor
    func registerSession(_
                         client: NeedleTailClient,
                         appleToken: String = "",
                         nameToVerify: String? = nil,
                         state: RegistrationState? = .full
    ) async throws {
        
        switch registrationState {
        case .full:
            let regObject = regRequest(with: appleToken)
            let packet = try BSONEncoder().encode(regObject).makeData()
            try await client.transport?.registerNeedletailSession(packet)
        case .temp:
            let regObject = regRequest(true)
            let packet = try BSONEncoder().encode(regObject).makeData()
            try await client.transport?.registerNeedletailSession(packet, true)
        }
    }
    
    @NeedleTailClientActor
    func createClient(_ nameToVerify: String? = nil) async throws -> NeedleTailClient {
        do {
            guard await self.client?.transport?.channel == nil else { throw NeedleTailError.channelExists }
            guard self.client == nil else { throw NeedleTailError.clientExists }
        } catch {}
        
        var name: String?
        var deviceId: DeviceId?
        
        if signer?.username.raw != nil {
            name = signer?.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
        } else {
            name = nameToVerify?.replacingOccurrences(of: " ", with: "").ircLowercased()
        }
        
        if signer?.deviceId == nil {
            deviceId = DeviceId("")
        } else {
            deviceId = signer?.deviceId
        }
        
        guard let name = name else { throw NeedleTailError.nilNickName }
        self.needleTailNick = NeedleTailNick(name: name, deviceId: deviceId)
        guard let nick = self.needleTailNick else { throw NeedleTailError.nilNickName }
        
        let clientContext = ClientContext(
            clientInfo: self.clientInfo,
            nickname: nick
        )
        
        let newClient = await NeedleTailClient(
            cypher: cypher,
            messenger: self,
            transportState: self.transportState,
            transportDelegate: self.delegate,
            signer: signer,
            clientContext: clientContext
        )
        self.client = newClient
        try await connect()
        return newClient
    }
    
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    @NeedleTailClientActor
    public func publishKeyBundle(_ data: UserConfig) async throws {
        guard let client = self.client else { throw NeedleTailError.nilClient }
        guard let transport = self.client?.transport else { throw NeedleTailError.transportNotIntitialized }
        guard let username = username else { return }
        guard isConnected else { return }
        // We want to set a recipient if we are adding a new device and we want to set a tag indicating we are registering a new device
        let updateKeyBundle = transport.updateKeyBundle
        
        var contacts: [NTKContact]?
        if updateKeyBundle {
            contacts = [NTKContact]()
            for contact in try await cypher?.listContacts() ?? [] {
                await contacts?.append(
                    NTKContact(
                        username: contact.username,
                        nickname: contact.nickname ?? ""
                    )
                )
            }
        }
        
        switch await transportState.current {
        case .transportOffline:
            try await startSession(
                client,
                type: registrationType(appleToken ?? ""),
                nameToVerify: nil,
                state: registrationState
            )
        default:
            break
        }
        
        try await RunLoop.run(240, sleep: 1, stopRunning: {
            var running = true
            
            if await transport.acknowledgment == .registered("true") {
                running = false
            }
            
            switch await transportState.current {
            case .transportOnline(channel: _, nick: _, userInfo: _):
                running = false
            default:
                running = true
            }
            return running
        })
        
        let jwt = try makeToken()
        let configObject = configRequest(jwt, config: data, recipientDeviceId: self.recipientDeviceId)
        let bundleData = try BSONEncoder().encode(configObject).makeData()
        self.keyBundle = bundleData.base64EncodedString()
        
        let recipient = try await transport.recipient(conversationType: type, deviceId: self.deviceId, name: "\(username.raw)")
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .publishKeyBundle(self.keyBundle),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            addKeyBundle: updateKeyBundle,
            contacts: contacts
        )
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await transport.transportMessage(type)
        
        
        
        try await RunLoop.run(240, sleep: 1, stopRunning: {
            var running = true
            if await transport.acknowledgment == .publishedKeyBundle("true") {
                running = false
            }
            return running
        })
        if await transport.acknowledgment != .publishedKeyBundle("true") {
            throw NeedleTailError.cannotPublishKeyBundle
        }
    }
    
    /// When we initially create a user we need to read the key bundle upon registration. Since the User is created on the Server a **UserConfig** exists.
    /// Therefore **CypherTextKit** will ask to read that users bundle. If It does not exist then the error is caught and we will call ``publishKeyBundle(_ data:)``
    /// from **CypherTextKit**'s **registerMessenger()** method.
    @NeedleTailClientActor
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        guard let transport = client?.transport else { throw NeedleTailError.transportNotIntitialized }
        // We need to set the userConfig to nil for the next read flow
        transport.userConfig = nil
        let jwt = try makeToken()
        
        
        
        
        //TODO: We are always sending self deviceId, we need to get the deviceId for the bundle we are requesting.. HOW DO WE GET A USERNAME'S SPECIFIC KEY BUNDLE????
        //1. We can get all usernames keybundles and filter the one we want according to the state we are in or???
        //2.
        
        
        
        
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData()
        var userConfig: UserConfig? = nil
        
        try await RunLoop.run(240, sleep: 1, stopRunning: {
            var running = true
            if client != nil {
                userConfig = try await transport.readKeyBundle(packet.base64EncodedString())
                running = false
            }
            return running
        })
        guard let userConfig = userConfig else {
            throw NeedleTailError.nilUserConfig
            
        }
        return userConfig
    }
    
    @NeedleTailClientActor
    public func requestDeviceRegistration(_ nick: NeedleTailNick) async throws {
        guard let transport = client?.transport else { throw NeedleTailError.transportNotIntitialized }
        try await transport.sendDeviceRegistryRequest(nick)
    }
    
    @NeedleTailClientActor
    public func processApproval(_ code: String) async throws -> Bool {
        guard let transport = client?.transport else { throw NeedleTailError.transportNotIntitialized }
        return await transport.computeApproval(code)
    }
    
    @NeedleTailClientActor
    func addMasterDevicesContacts(_ contactList: [NTKContact]) async throws {
        for contact in contactList {
            print("CONTACT__", contact)
            let createdContact = try await cypher?.createContact(byUsername: contact.username)
            try await createdContact?.setNickname(to: contact.nickname)
        }
    }
    
    @NeedleTailTransportActor
    public func registerAPNSToken(_ token: Data) async throws {
        guard let deviceId = deviceId else { return }
        guard let username = username else { return }
        
        let jwt = try makeToken()
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData()
        guard let transport = await client?.transport else { throw NeedleTailError.transportNotIntitialized }
        let recipient = try await transport.recipient(conversationType: type, deviceId: deviceId, name: "\(username.raw)")
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .registerAPN(payload.base64EncodedString()),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await transport.transportMessage(type)
    }
    
    private func makeToken() throws -> String {
        guard let signer = signer else { return "" }
        guard let username = username else { return "" }
        guard let deviceId = deviceId else { return "" }
        
        var signerAlgorithm: JWTAlgorithm
#if os(Linux)
        signerAlgorithm = signer as! JWTAlgorithm
#else
        signerAlgorithm = signer
#endif
        return try JWTSigner(algorithm: signerAlgorithm)
            .sign(
                Token(
                    device: UserDeviceId(user: username, device: deviceId),
                    exp: ExpirationClaim(value: Date().addingTimeInterval(3600))
                )
            )
    }
    
    func regRequest(with appleToken: String = "", _ tempRegister: Bool = false) -> AuthPacket {
        return AuthPacket(
            appleToken: appleToken,
            username: signer?.username,
            deviceId: signer?.deviceId,
            config: signer?.userConfig,
            tempRegister: tempRegister
        )
    }
    
    func configRequest(_ jwt: String, config: UserConfig, recipientDeviceId: DeviceId? = nil) -> AuthPacket {
        return AuthPacket(
            jwt: jwt,
            username: self.username,
            deviceId: self.deviceId,
            config: config,
            tempRegister: false,
            recipientDeviceId: recipientDeviceId
        )
    }
    
    private func apnRequest(_
                            jwt: String,
                            apnToken: String,
                            deviceId: DeviceId
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            apnToken: apnToken,
            username: self.username,
            deviceId: deviceId,
            tempRegister: false
        )
    }
    
    private func readBundleRequest(_
                                   jwt: String,
                                   recipient: Username
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            username: self.username,
            recipient: recipient,
            deviceId: deviceId,
            tempRegister: false
        )
    }
    
    
    struct SignUpResponse: Codable {
        let existingUser: Username?
    }
    
    
    @NeedleTailClientActor
    func connect() async throws {
        guard let client = self.client else { throw NeedleTailError.nilClient }
        try await client.attemptConnection()
        self.authenticated = .authenticated
    }
    
    @NeedleTailClientActor
    func suspend(_ isSuspending: Bool = false) async {
        do {
            guard let client = self.client else { throw NeedleTailError.nilClient }
            try await client.attemptDisconnect(isSuspending)
        } catch {
            await shutdownClient()
        }
    }
    
    @NeedleTailClientActor
    func shutdownClient() async {
        do {
            guard let client = self.client else { throw NeedleTailError.nilClient }
            guard let channel = client.channel else { throw NeedleTailError.channelIsNil }
            _ = try await channel.close(mode: .all).get()
            try await client.groupManager.shutdown()
            self.client = nil
            isConnected = false
            logger.info("disconnected from server")
            await transportState.transition(to: .clientOffline)
        } catch {
            logger.error("Could not gracefully shutdown, Forcing the exit (\(error))")
            exit(0)
        }
    }
}

public enum RegistrationType {
    case siwa(String), plain
}

public enum RegistrationState {
    case full, temp
}


extension NeedleTailMessenger {
    
    public func reconnect() async throws {}
    
    public func disconnect() async throws {}
    
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func sendMessageReceivedReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    /// When we request a new device registration. We generate a QRCode that the master device needs to scan. Once that is scanned, the master device should notify via a server request/response to the child in order to set masterScanned to true. The the new device can register to IRC and receive messages with that username.
    /// - Parameter config: The Requesters User Device Configuration
    @NeedleTailClientActor
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {
        guard let client = self.client else { throw NeedleTailError.nilClient }
        
        switch await transportState.current {
        case .transportOffline:
            try await startSession(
                client,
                type: registrationType(appleToken ?? ""),
                nameToVerify: nil,
                state: registrationState
            )
        default:
            break
        }
        
        //rebuild the device config sp we can create a master device
        let newMaster = UserDeviceConfig(
            deviceId: config.deviceId,
            identity: config.identity,
            publicKey: config.publicKey,
            isMasterDevice: true
        )
        logger.info("We are requesting a Device Registry with this configuration: \(newMaster)")
        let bsonData = try BSONEncoder().encode(newMaster).makeData()
        let base64String = bsonData.base64EncodedString()
        let data = base64String.data(using: .ascii)
#if (os(macOS) || os(iOS))
        await MainActor.run {
            plugin.emitter.showScanner = false
            // Send user config data to generate a QRCode in the requesting client
            plugin.emitter.received = nil
            plugin.emitter.qrCodeData = data
        }
#endif
        
        try await RunLoop.run(240, sleep: 1) {
            var running = true
#if (os(macOS) || os(iOS))
            if plugin.emitter.qrCodeData == nil {
                running = false
            }
#endif
            return running
        }
    }
    
    /// This method is called when we send a PRIVMSG Packet that is specified as a .requestDeviceRegistery Packet. We then call it on our inbound handler. This is only called when the device created is not a master device.
    public func onDeviceRegisteryRequest(_ config: UserDeviceConfig, messenger: CypherMessenger) async throws {
        print(#function)
        try await messenger.addDevice(config)
    }
    
    public struct SetToken: Codable {
        let token: String
    }
    
    public func setDelegate(to delegate: CypherTransportClientDelegate) async throws {
        self.delegate = delegate
    }
    
    @BlobActor
    public func publishBlob<C>(_ blob: C) async throws -> ReferencedBlob<C> where C : Decodable, C : Encodable {
        guard let transport = await client?.transport else { throw NeedleTailError.transportNotIntitialized }
        let blobString = try BSONEncoder().encode(blob).makeData()
        try await transport.publishBlob(blobString.base64EncodedString())
        
        guard let channelBlob = await transport.channelBlob else { throw NeedleTailError.nilBlob }
        guard let data = Data(base64Encoded: channelBlob) else { throw NeedleTailError.nilData }
        let blob = try BSONDecoder().decode(NeedleTailHelpers.Blob<C>.self, from: Document(data: data))
        return ReferencedBlob(id: blob._id, blob: blob.document)
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
        transport: NeedleTailTransport,
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
        
        
        guard let cypher = cypher else { return }
        let metaDoc = try BSONEncoder().encode(needleTailChannelMetaData)
        
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
        try await transport.createNeedleTailChannel(
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
        _ = await plugin.emitter.fetchChats(cypher: cypher)
        let groupChats = try await plugin.emitter.fetchGroupChats(cypher)
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
    
    /// We are getting the message from CypherTextKit after Encryption. Our Client will send it to CypherTextKit Via `sendRawMessage()`
    @NeedleTailTransportActor
    public func sendMessage(_
                            message: RatchetedCypherMessage,
                            toUser username: Username,
                            otherUserDeviceId deviceId: DeviceId,
                            pushType: PushType,
                            messageId: String
    ) async throws {
        guard let transport = await client?.transport else { throw NeedleTailError.transportNotIntitialized }
        guard let myDeviceId = self.deviceId else { return }
        switch type {
        case .groupMessage(let name):
            try await transport.createGroupMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                channelName: name,
                fromDevice: myDeviceId,
                toUser: username,
                toDevice: deviceId,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt)
        case .privateMessage:
            try await transport.createPrivateMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                fromDevice: myDeviceId,
                toUser: username,
                toDevice: deviceId,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt)
        }
    }
    
    public func sendMultiRecipientMessage(_ message: MultiRecipientCypherMessage, pushType: PushType, messageId: String) async throws {
        fatalError("AsyncIRC Doesn't support sendMultiRecipientMessage() in this manner")
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
        let hexLen = self.count * 2
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: hexLen)
        //        var bytes = [UInt8]()
        var offset = 0
        
        self.regions.forEach { (_) in
            for i in self {
                bytes[Int(offset * 2)] = itoh((i >> 4) & 0xF)
                bytes[Int(offset * 2 + 1)] = itoh(i & 0xF)
                offset += 1
            }
        }
        
        //        return String(buffer: ByteBuffer(bytes: bytes))
        return String(bytesNoCopy: bytes, length: hexLen, encoding: .utf8, freeWhenDone: true)!
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
