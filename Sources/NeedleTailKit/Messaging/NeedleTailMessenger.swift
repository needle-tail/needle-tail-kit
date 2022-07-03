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
    public var isConnected: Bool = false
    public var delegate: CypherTransportClientDelegate?
    public private(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    public var type : ConversationType = .privateMessage
    public private(set) var signer: TransportCreationRequest
    private(set) var needleTailNick: NeedleTailNick?
    private let username: Username
    private let appleToken: String?
    private var transportState: TransportState
    private var clientInfo: ClientContext.ServerClientInfo
    private var keyBundle: String = ""
    private var waitingToReadBundle: Bool = false
    var cypher: CypherMessenger?
    var client: NeedleTailTransportClient?
    var plugin: NeedleTailPlugin
    var logger: Logger
    var messageType = MessageType.message
    var readReceipt: ReadReceiptPacket?
    var needleTailChannelMetaData: NeedleTailChannelPacket?
    let deviceId: DeviceId
    var shouldProceedRegistration = true
    var initalRegistration = false
    
    
    @NeedleTailTransportActor
    public init(
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
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
    
    @NeedleTailTransportActor
    public class func authenticate(
        appleToken: String? = "",
        transportRequest: TransportCreationRequest,
        clientInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin
    ) async throws -> NeedleTailMessenger {
        return try await NeedleTailMessenger(
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest,
            appleToken: appleToken,
            transportState: TransportState(identifier: UUID()),
            clientInfo: clientInfo,
            plugin: plugin
        )
    }
    
    @NeedleTailTransportActor
    public func registrationType(_ appleToken: String = "") -> RegistrationType? {
        var type: RegistrationType?
        if !appleToken.isEmpty {
            type = .siwa(appleToken)
        } else {
            type = .plain
        }
        return type
    }
    
    @NeedleTailTransportActor
    public func startSession(_ type: RegistrationType?) async throws {
        switch type {
        case .siwa(let apple):
            try await self.registerSession(apple)
        case .plain:
            try await self.registerSession()
        default:
            break
        }
    }
    
    @NeedleTailTransportActor
    public func registerSession(_ appleToken: String = "") async throws {
        if client?.channel == nil {
            await createClient()
        }
        let regObject = regRequest(with: appleToken)
        let packet = try BSONEncoder().encode(regObject).makeData().base64EncodedString()
        await client?.registerNeedletailSession(packet)
    }
    
    @NeedleTailTransportActor
    public func createClient() async {
        if client == nil {
            let lowerCasedName = signer.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
            guard let nick = NeedleTailNick(name: lowerCasedName, deviceId: signer.deviceId) else { return }
            let clientContext = ClientContext(
                clientInfo: self.clientInfo,
                nickname: nick
            )
            
            guard let cypher = self.cypher else { return }
            client = await NeedleTailTransportClient(
                cypher: cypher,
                messenger: self,
                transportState: self.transportState,
                transportDelegate: self.delegate,
                signer: self.signer,
                authenticated: self.authenticated,
                clientContext: clientContext)
            
            self.needleTailNick = nick
        }
        await connect()
    }
    
    
    /// We only Publish Key Bundles when a user is adding mutli-devcie support.
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    @KeyBundleActor
    public func publishKeyBundle(_ data: UserConfig) async throws {
        if shouldProceedRegistration == true && isConnected == true && initalRegistration {
            try await startSession(registrationType(appleToken ?? ""))
            repeat {} while await client?.acknowledgment != .registered("true")
        }
        
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }
        let configObject = configRequest(jwt, config: data)
        self.keyBundle = try BSONEncoder().encode(configObject).makeData().base64EncodedString()
        guard let client = client else { return }
        let recipient = try await client.recipient(conversationType: type, deviceId: self.deviceId, name: "\(username.raw)")
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .publishKeyBundle(self.keyBundle),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        
        let data = try BSONEncoder().encode(packet).makeData()
        _ = await client.sendPrivateMessage(data, to: recipient, tags: nil)
        //        client?.acknowledgment = .none
    }
    
    /// When we initially create a user we need to read the key bundle upon registration. Since the User is created on the Server a **UserConfig** exists.
    /// Therefore **CypherTextKit** will ask to read that users bundle. If It does not exist then the error is caught and we will call ``publishKeyBundle(_ data:)``
    /// from **CypherTextKit**'s **registerMessenger()** method.
    @NeedleTailTransportActor
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        guard let client = self.client else { throw NeedleTailError.nilClient }
        let date = RunLoop.timeInterval(10)
        var canRun = false
        var userConfig: UserConfig? = nil
        repeat {
            canRun = true
            if client.channel != nil {
                userConfig = await client.readKeyBundle(packet)
                canRun = false
            }
        } while await RunLoop.execute(date, ack: client.acknowledgment, canRun: canRun)
        guard let userConfig = userConfig else { throw NeedleTailError.nilUserConfig }
        return userConfig
    }
    
    @NeedleTailTransportActor
    public func registerAPNSToken(_ token: Data) async throws {
        guard let jwt = makeToken() else { return }
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: self.deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData().base64EncodedString()
        guard let client = client else { return }
        let recipient = try await client.recipient(conversationType: type, deviceId: deviceId, name: "\(username.raw)")
        
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
        
        let data = try BSONEncoder().encode(packet).makeData()
        _ = await client.sendPrivateMessage(data, to: recipient, tags: nil)
        
    }
    
    private func makeToken() -> String? {
        var signerAlgorithm: JWTAlgorithm
#if os(Linux)
        signerAlgorithm = signer as! JWTAlgorithm
#else
        signerAlgorithm = signer
#endif
        return try? JWTSigner(algorithm: signerAlgorithm)
            .sign(
                Token(
                    device: UserDeviceId(user: self.username, device: self.deviceId),
                    exp: ExpirationClaim(value: Date().addingTimeInterval(3600))
                )
            )
    }
    
    private func regRequest(with appleToken: String) -> AuthPacket {
        return AuthPacket(
            jwt: nil,
            appleToken: appleToken,
            apnToken: nil,
            username: signer.username,
            recipient: nil,
            deviceId: signer.deviceId,
            config: signer.userConfig
        )
    }
    
    private func configRequest(_ jwt: String, config: UserConfig) -> AuthPacket {
        return AuthPacket(
            jwt: jwt,
            appleToken: nil,
            apnToken: nil,
            username: self.username,
            recipient: nil,
            deviceId: self.deviceId,
            config: config
        )
    }
    
    private func apnRequest(_
                            jwt: String,
                            apnToken: String,
                            deviceId: DeviceId
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            appleToken: nil,
            apnToken: apnToken,
            username: self.username,
            recipient: nil,
            deviceId: deviceId,
            config: nil
        )
    }
    
    private func readBundleRequest(_
                                   jwt: String,
                                   recipient: Username
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            appleToken: nil,
            apnToken: nil,
            username: self.username,
            recipient: recipient,
            deviceId: deviceId,
            config: nil
        )
    }
    
    struct AuthPacket: Codable {
        let jwt: String?
        let appleToken: String?
        let apnToken: String?
        let username: Username
        let recipient: Username?
        let deviceId: DeviceId?
        let config: UserConfig?
    }
    
    
    struct SignUpResponse: Codable {
        let existingUser: Username?
    }
    
    
    @NeedleTailTransportActor
    public func connect() async {
        do {
            //TODO: State Error
            guard transportState.current == .offline || transportState.current == .suspended else { return }
            try await client?.attemptConnection()
            self.authenticated = .authenticated
            if client?.channel != nil {
                self.isConnected = true
            }
        } catch {
            transportState.transition(to: .offline)
            self.authenticated = .authenticationFailure
            await connect()
        }
    }
    
    @NeedleTailTransportActor
    public func suspend(_ isSuspending: Bool = false) async {
        //TODO: State Error
        await client?.attemptDisconnect(isSuspending)
        client = nil
    }
}

public enum RegistrationType {
    case siwa(String), plain
}



extension NeedleTailMessenger {
    
    public func reconnect() async throws {}
    
    public func disconnect() async throws {}
    
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func sendMessageReceivedReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    /// For our IRC Setup we need to react when we are trying to register a new device by doing the following.
    /// 1. Send the new Device Config to the Server in order to notify the current Nick that we want to request registry.
    /// 2. The other party(**Master Device**) will then need to respond to the request and send us the **newDeviceState**
    /// 3. Loop until we get back a response from the server with the decision made by the master device whether or not that we accepted the registration request.
    /// 4. If the decision was to accept the registration we can notify CTK that we received the approval we we can finsish setting up the local device
    /// 5. When this method is complete then NTK should finish registering the new device into the IRC Session
    @NeedleTailTransportActor
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {
        print("We are requesting a Device Registry with this configuration: ", config)
        //Master nick
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        let keyBundle = await client?.readKeyBundle(packet)
        let masterDeviceConfig = try keyBundle?.readAndValidateDevices().first(where: { $0.isMasterDevice })
        let lowerCasedName = signer.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
        guard let masterNick = NeedleTailNick(name: lowerCasedName, deviceId: masterDeviceConfig?.deviceId) else {
            return
        }
        guard let childNick = NeedleTailNick(name: lowerCasedName, deviceId: self.deviceId) else {
            return
        }
        try await client?.sendDeviceRegistryRequest(masterNick, childNick: childNick)
        let date = RunLoop.timeInterval(10)
        var canRun = false
        repeat {
            canRun = true
            if newDeviceState == .waiting {
                canRun = false
            }
            /// We just want to run a loop until the newDeviceState isn't .waiting or stop on the timeout
        } while await RunLoop.execute(date, canRun: canRun)
        switch newDeviceState {
        case .accepted:
            try await client?.sendFinishRegistryMessage(toMaster: config, nick: masterNick)
        case .rejected:
            print("REJECTED__")
            shouldProceedRegistration = false
            return
        case .waiting:
            print("WAITING__")
            shouldProceedRegistration = false
            return
        case .isOffline:
            print("Offline__")
            shouldProceedRegistration = false
            return
        }
    }
    
    public func onDeviceRegisteryRequest(_ config: UserDeviceConfig, messenger: CypherMessenger) async throws {
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
        let blobString = try BSONEncoder().encode(blob).makeData().base64EncodedString()
        try await client?.publishBlob(blobString)
        
        guard let channelBlob = await client?.channelBlob else { throw NeedleTailError.nilBlob }
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
        try await client?.createNeedleTailChannel(
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
        guard let client = client else { return }
        guard let readReceipt = readReceipt else { return }
        switch type {
        case .groupMessage(let name):
            try await client.createGroupMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                channelName: name,
                fromDevice: self.deviceId,
                toUser: username,
                toDevice: deviceId,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt)
        case .privateMessage:
            try await client.createPrivateMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                fromDevice: self.deviceId,
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
