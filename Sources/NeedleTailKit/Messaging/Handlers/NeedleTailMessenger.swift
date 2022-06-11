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
    public var type : ConversationType = .im
    private let deviceId: DeviceId
    public private(set) var signer: TransportCreationRequest
    private let username: Username
    private let appleToken: String?
    public var registrationType: RegistrationType?
    private var transportState: TransportState
    private var clientInfo: ClientContext.ServerClientInfo
    private var keyBundle: String = ""
    private var waitingToReadBundle: Bool = false
    var messenger: CypherMessenger?
//    var services: IRCService?
    var client: NeedleTailTransportClient?
    var logger: Logger
    var messageType = MessageType.message
    var readRecipect: ReadReceiptPacket?
    var ircMessenger: NeedleTailMessenger?
    var shouldProceedRegistration = true
    
    public init(
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        appleToken: String?,
        transportState: TransportState,
        clientInfo: ClientContext.ServerClientInfo
    ) async throws {
        self.logger = Logger(label: "IRCMessenger - ")
        self.transportState = transportState
        self.clientInfo = clientInfo
        self.username = username
        self.deviceId = deviceId
        self.signer = signer
        self.appleToken = appleToken
    }

    
    
    public class func authenticate(
        appleToken: String? = "",
        transportRequest: TransportCreationRequest,
        clientInfo: ClientContext.ServerClientInfo
    ) async throws -> NeedleTailMessenger {
        return try await NeedleTailMessenger(
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest,
            appleToken: appleToken,
            transportState: TransportState(identifier: UUID()),
            clientInfo: clientInfo
        )
    }
    
    public func createClient() async {
        if client == nil {
        let lowerCasedName = signer.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
        guard let nick = NeedleTailNick(deviceId: signer.deviceId, name: lowerCasedName) else { return }
        let clientContext = ClientContext(
            clientInfo: self.clientInfo,
            nickname: nick
        )
        
        client = await NeedleTailTransportClient(
            cypher: self.messenger,
            transportState: self.transportState,
            transportDelegate: self.delegate,
            signer: self.signer,
            authenticated: self.authenticated,
            clientContext: clientContext)
        }
        await connect()
    }
    
    public func registerSession(_ appleToken: String = "") async throws {
        if await client?.channel == nil {
            await createClient()
        }
        let regObject = regRequest(with: appleToken)
        let packet = try BSONEncoder().encode(regObject).makeData().base64EncodedString()
        await client?.registerNeedletailSession(packet)
    }
    
    
    public func registerBundle(
        type: RegistrationType?,
        clientInfo: ClientContext.ServerClientInfo
    ) async throws {
        switch type {
        case .siwa, .plain:
            waitingToReadBundle = true
            guard let appleToken = appleToken else { return }
            try await self.registerSession(appleToken)
        case .none:
            break
        }
    }
    
    /// We only Publish Key Bundles when a user is adding mutli-devcie support.
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    @NeedleTailTransportActor
    public func publishKeyBundle(_ data: UserConfig) async throws {
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }
        let configObject = configRequest(jwt, config: data)
        self.keyBundle = try BSONEncoder().encode(configObject).makeData().base64EncodedString()
        let recipient = try await recipient(deviceId: self.deviceId, name: "\(username.raw)")

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
        _ = await client?.sendPrivateMessage(data, to: recipient, tags: nil)
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
    
    
    public func registerAPNSToken(_ token: Data) async throws {
        guard let jwt = makeToken() else { return }
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: self.deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData().base64EncodedString()
        let recipient = try await recipient(deviceId: deviceId, name: "\(username.raw)")
        
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
        _ = await client?.sendPrivateMessage(data, to: recipient, tags: nil)
        
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
    
    
    // MARK: - services Lookup
    
    
//    internal func serviceWithID(_ id: String) -> IRCService? {
//        guard let uuid = UUID(uuidString: id) else { return nil }
//        return serviceWithID(uuid.uuidString)
//    }
    
    public func removeAccountWithID(_ id: UUID) {
        
    }
    
    @NeedleTailTransportActor
    public func connect() async {
        do {
            //TODO: State Error
            guard transportState.current == .offline || transportState.current == .suspended else { return }
            try await client?.attemptConnection()
            self.authenticated = .authenticated
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
    case siwa, plain
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
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {
        print("We are requesting a Device Registry with this configuration: ", config)
        //Master nick
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        let keyBundle = await client?.readKeyBundle(packet)
        let masterDeviceConfig = try keyBundle?.readAndValidateDevices().first(where: { $0.isMasterDevice })
        let lowerCasedName = signer.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
        guard let masterNick = NeedleTailNick(deviceId: masterDeviceConfig?.deviceId, name: lowerCasedName) else {
            return
        }
        guard let childNick = NeedleTailNick(deviceId: self.deviceId, name: lowerCasedName) else {
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
    
    public func publishBlob<C>(_ blob: C) async throws -> ReferencedBlob<C> where C : Decodable, C : Encodable {
        fatalError()
    }
    
    public func readPublishedBlob<C>(byId id: String, as type: C.Type) async throws -> ReferencedBlob<C>? where C : Decodable, C : Encodable {
        fatalError()
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

        let packet = MessagePacket(
            id: messageId,
            pushType: pushType,
            type: self.messageType,
            createdAt: Date(),
            sender: self.deviceId,
            recipient: deviceId,
            message: message,
            readReceipt: self.readRecipect
        )
        
        let data = try BSONEncoder().encode(packet).makeData()
        do {
            let ircUser = username.raw.replacingOccurrences(of: " ", with: "").lowercased()
            let recipient = try await recipient(deviceId: self.deviceId, name: "\(ircUser)")
            await client?.sendPrivateMessage(data, to: recipient, tags: [
                IRCTags(key: "senderDeviceId", value: "\(self.deviceId)"),
                IRCTags(key: "recipientDeviceId", value: "\(deviceId)")
            ])
        } catch {
            logger.error("\(error)")
        }
    }
    
    
    public func recipient(deviceId: DeviceId, name: String) async throws -> IRCMessageRecipient {
        switch type {
        case .channel:
            guard let name = IRCChannelName(name) else { throw NeedleTailError.nilChannelName }
            return .channel(name)
        case .im:
            guard let validatedName = NeedleTailNick(deviceId: deviceId, name: name) else { throw NeedleTailError.nilNickName }
            return .nickname(validatedName)
        }
    }
    
    public func sendMultiRecipientMessage(_ message: MultiRecipientCypherMessage, pushType: PushType, messageId: String) async throws {
        fatalError("AsyncIRC Doesn't support sendMultiRecipientMessage() in this manner")
    }
    
    public enum ConversationType: Equatable {
        case channel
        case im
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
