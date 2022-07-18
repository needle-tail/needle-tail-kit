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
import AsyncIRC
import NeedleTailHelpers
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import NIOTransportServices
#endif

public class NeedleTailMessenger: CypherServerTransportClient {
    public var isConnected: Bool = true
    public var delegate: CypherTransportClientDelegate?
    public private(set) var authenticated = AuthenticationState.unauthenticated
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
    var readReceipt: ReadReceiptPacket?
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
            transportState: TransportState(identifier: UUID()),
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
    public func startSession(
        _ type: RegistrationType,
        _ state: RegistrationState? = .full
    ) async throws {
        switch type {
        case .siwa(let apple):
            try await self.registerSession(apple)
        case .plain:
            try await self.registerSession()
        }
    }
    
    @NeedleTailClientActor
    public func registerSession(_
                                appleToken: String = "",
                                nameToVerify: String? = nil,
                                state: RegistrationState? = .full
    ) async throws {
        if client?.channel == nil {
            try await createClient(nameToVerify)
        }
        
        switch registrationState {
        case .full:
            let regObject = regRequest(with: appleToken)
            let packet = try BSONEncoder().encode(regObject).makeData().base64EncodedString()
            try await client?.transport?.registerNeedletailSession(packet)
        case .temp:
            let regObject = regRequest(true)
            let packet = try BSONEncoder().encode(regObject).makeData().base64EncodedString()
            try await client?.transport?.registerNeedletailSession(packet, true)
        }
    }
    
    @NeedleTailClientActor
    public func createClient(_ nameToVerify: String? = nil) async throws {
        if client == nil {
            var name: String?
            if signer?.username.raw != nil {
                name = signer?.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
            } else {
                name = nameToVerify?.ircLowercased()
            }
            guard let name = name else { return }
            guard let nick = NeedleTailNick(name: name, deviceId: signer?.deviceId) else { throw NeedleTailError.nilNickName }
            let clientContext = ClientContext(
                clientInfo: self.clientInfo,
                nickname: nick
            )
            
            client = await NeedleTailClient(
                cypher: cypher,
                messenger: self,
                transportState: self.transportState,
                transportDelegate: self.delegate,
                signer: signer,
                authenticated: self.authenticated,
                clientContext: clientContext
            )
            
            self.needleTailNick = nick
        }
        try await connect()
    }
    
    //TODO: Have exit point be in transport+outbound
    /// We only Publish Key Bundles when a user is adding mutli-devcie support.
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    @NeedleTailClientActor
    public func publishKeyBundle(_ data: UserConfig) async throws {
        guard let username = username else { return }
        guard isConnected else { return }
        
        try await startSession(registrationType(appleToken ?? ""), registrationState)
        let date = RunLoop.timeInterval(10)
        var canRun = false
        repeat {
            canRun = true
            if await client?.transport?.acknowledgment != .registered("true") {
                canRun = false
            }
        } while await RunLoop.execute(date, canRun: canRun)

        let jwt = try makeToken()
        let configObject = configRequest(jwt, config: data, recipientDeviceId: self.recipientDeviceId)
        self.keyBundle = try BSONEncoder().encode(configObject).makeData().base64EncodedString()
        guard let transport = client?.transport else { throw NeedleTailError.transportNotIntitialized }
        let recipient = try await transport.recipient(conversationType: type, deviceId: self.deviceId, name: "\(username.raw)")
        // We want to set a recipient if we are adding a new device and we want to set a tag indicating we are registering a new device
        let updateKeyBundle = client?.transport?.updateKeyBundle
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .publishKeyBundle(self.keyBundle),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            addKeyBundle: updateKeyBundle
        )
        
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        guard let channel = transport.channel else { return }
        try await transport.transportMessage(channel, type: type)
    }
    
    /// When we initially create a user we need to read the key bundle upon registration. Since the User is created on the Server a **UserConfig** exists.
    /// Therefore **CypherTextKit** will ask to read that users bundle. If It does not exist then the error is caught and we will call ``publishKeyBundle(_ data:)``
    /// from **CypherTextKit**'s **registerMessenger()** method.
    @NeedleTailClientActor
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        let jwt = try makeToken()
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        let date = RunLoop.timeInterval(10)
        var canRun = false
        var userConfig: UserConfig? = nil
        guard let transport = client?.transport else { throw NeedleTailError.transportNotIntitialized }
        repeat {
            canRun = true
            if client?.channel != nil {
                userConfig = try await transport.readKeyBundle(packet)
                canRun = false
            }
        } while await RunLoop.execute(date, ack: transport.acknowledgment, canRun: canRun)
        guard let userConfig = userConfig else { throw NeedleTailError.nilUserConfig }
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
    
    @NeedleTailTransportActor
    public func registerAPNSToken(_ token: Data) async throws {
        guard let deviceId = deviceId else { return }
        guard let username = username else { return }
        
        let jwt = try makeToken()
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData().base64EncodedString()
        guard let transport = await client?.transport else { return }
        let recipient = try await transport.recipient(conversationType: type, deviceId: deviceId, name: "\(username.raw)")
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .registerAPN(payload),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        guard let channel = await transport.channel else { return }
        try await transport.transportMessage(channel, type: type)
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
    public func connect() async throws {
        try await client?.attemptConnection()
        self.authenticated = .authenticated
        if client?.channel != nil {
            self.isConnected = true
        }
    }
    
    @NeedleTailClientActor
    public func suspend(_ isSuspending: Bool = false) async {
        //TODO: State Error
        await client?.attemptDisconnect(isSuspending)
        client = nil
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
    @NeedleTailTransportActor
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {
        //rebuild the device config sp we can creaete a master device
       let newMaster = UserDeviceConfig(
            deviceId: config.deviceId,
            identity: config.identity,
            publicKey: config.publicKey,
            isMasterDevice: true
)

        print("We are requesting a Device Registry with this configuration: ", newMaster)
#if (os(macOS) || os(iOS))
        try await MainActor.run {
            // Send user config data to generate a QRCode in the requesting client
                let data = try BSONEncoder().encode(newMaster).makeData()
            plugin.emitter.qrCodeData = data
        }
#endif
        //Loop until the master scans the code
        let date = RunLoop.timeInterval(10)
        var canRun = false
        repeat {
            canRun = true
            // After the Master scans the server will send us a response allowing us to proceed with registration
            if await client?.transport?.receivedNewDeviceAdded == .waiting {
              canRun = false
            }

        } while await RunLoop.execute(date, canRun: canRun)
    }
    
    public func onDeviceRegisteryRequest(_ config: UserDeviceConfig, messenger: CypherMessenger) async throws {
        print(#function)
//        try await messenger.addDevice(config)
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
        let blobString = try BSONEncoder().encode(blob).makeData().base64EncodedString()
        try await transport.publishBlob(blobString)
        
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
        name: String,
        admin: Username,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) async throws {
        guard let transport = await client?.transport else { throw NeedleTailError.transportNotIntitialized }
        
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
        guard let readReceipt = readReceipt else { return }
        guard let deviceId = self.deviceId else { return }
        switch type {
        case .groupMessage(let name):
            try await transport.createGroupMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                channelName: name,
                fromDevice: deviceId,
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
                fromDevice: deviceId,
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
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: hexLen)
        var offset = 0
        
        self.regions.forEach { (_) in
            for i in self {
                ptr[Int(offset * 2)] = itoh((i >> 4) & 0xF)
                ptr[Int(offset * 2 + 1)] = itoh(i & 0xF)
                offset += 1
            }
        }
        
        return String(bytesNoCopy: ptr, length: hexLen, encoding: .utf8, freeWhenDone: true)!
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
