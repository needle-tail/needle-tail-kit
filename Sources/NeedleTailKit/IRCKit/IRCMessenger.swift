//
//  IRCMessenger.swift
//
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIOCore
import NIOPosix
import CypherMessaging
import CypherProtocol
import Crypto
import AsyncIRC
import MessagingHelpers
import BSON
import JWTKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import NIOTransportServices
#endif

public class IRCMessenger: CypherServerTransportClient {
    public var isConnected: Bool = true
    public var delegate: CypherTransportClientDelegate?
    public private(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    public var type : ConversationType = .im
    private let deviceId: DeviceId
    private(set) var signer: TransportCreationRequest
    private let username: Username
    private let appleToken: String?
    public var registrationType: RegistrationType?
    internal var services: IRCService?
    private var userState: UserState
    private var clientOptions: ClientOptions?
    internal var messenger: CypherMessenger?
    private var keyBundle: String = ""
    private var waitingToReadBundle: Bool = false
    
    public init(
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        appleToken: String?,
        userState: UserState,
        clientOptions: ClientOptions?
    ) async throws {
        self.userState = userState
        self.clientOptions = clientOptions
        self.username = username
        self.deviceId = deviceId
        self.signer = signer
        self.appleToken = appleToken
    }
    
    public class func authenticate(
        appleToken: String? = "",
        transportRequest: TransportCreationRequest,
        options: ClientOptions?
    ) async throws -> IRCMessenger {
        return try await IRCMessenger(
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest,
            appleToken: appleToken,
            userState: UserState(identifier: ""),
            clientOptions: options
        )
    }
    
    public func startService(_ packet: String? = nil) async {
        if self.services == nil {
            self.services = await IRCService(
                signer: self.signer,
                authenticated: self.authenticated,
                userState: self.userState,
                clientOptions: clientOptions,
                delegate: self.delegate
            )
        }
        await resume(packet)
    }
    
    public func registerBundle(
        type: RegistrationType?,
        options: ClientOptions
    ) async throws {
        switch type {
        case .siwa, .plain:
            waitingToReadBundle = true
            guard let appleToken = appleToken else { return }
            let regObject = regRequest(with: appleToken)
            let packet = try BSONEncoder().encode(regObject).makeData().base64EncodedString()
            await self.startService(packet)
        case .none:
            break
        }
    }
    
    /// We only Publish Key Bundles when a user is adding mutli-devcie support.
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    public func publishKeyBundle(_ data: UserConfig) async throws {
        waitingToReadBundle = true
        guard let jwt = makeToken() else { throw IRCClientError.nilToken }
        let configObject = configRequest(jwt, config: data)
        self.keyBundle = try BSONEncoder().encode(configObject).makeData().base64EncodedString()
        await self.services?.client?.publishKeyBundle(self.keyBundle)
    }
    
    /// When we initially create a user we need to read the key bundle upon registration. Since the User first is created on the Server a **UserConfig** exists.
    /// Therefore **CypherTextKit** will ask to read that users bundle. If It does not exist then the error is causght and we will call ``publishKeyBundle(_ data:)``
    /// from **CypherTextKit**'s **registerMessenger()** method.
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        guard let jwt = makeToken() else { throw IRCClientError.nilToken }
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        guard let services = services else { throw IRCClientError.nilService }
        
        var userConfig: UserConfig?
        
        if !waitingToReadBundle {
            userConfig = await services.readKeyBundle(packet)
        } else {
            repeat {
                switch services.acknowledgment {
                case .registered(let registered):
                    if Bool(registered) != nil {
                        userConfig = await services.readKeyBundle(packet)
                    }
                    waitingToReadBundle = false
                default:
                    break
                }
            } while services.acknowledgment == .none
        }
        
        guard let userConfig = userConfig else { throw IRCClientError.nilUsedConfig }
        services.acknowledgment = .none
        return userConfig
    }
    
    
    public func registerAPNSToken(_ token: Data) async throws {
        guard let jwt = makeToken() else { return }
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: self.deviceId)
        let packet = try BSONEncoder().encode(apnObject).makeData().base64EncodedString()
        await self.services?.registerAPN(packet)
    }
    
    private func makeToken() -> String? {
        return try? JWTSigner(algorithm: signer as! JWTAlgorithm).sign(
            Token(
                device: UserDeviceId(user: self.username, device: self.deviceId),
                exp: .init(value: Date().addingTimeInterval(3600))
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
    internal func serviceWithID(_ id: String) -> IRCService? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return serviceWithID(uuid.uuidString)
    }
    
    public func removeAccountWithID(_ id: UUID) {
        
    }
    
    // MARK: - Lifecycle
    public func resume(_ regPacket: String? = nil) async {
        do {
            try await services?.resume(regPacket)
            self.authenticated = .authenticated
        } catch {
            self.authenticated = .authenticationFailure
            await resume(regPacket)
        }
    }
    
    public func suspend() async {
        await services?.suspend()
        self.authenticated = .unauthenticated
    }
    
    public func close() async {
        await services?.close()
    }
}

public enum RegistrationType {
    case siwa, plain
}

struct IRCCypherMessage<Message: Codable>: Codable {
    var message: Message
    var pushType: PushType
    var messageId: String
    var token: String?
    
    init(
        message: Message,
        pushType: PushType,
        messageId: String,
        token: String?
    ) {
        self.message = message
        self.pushType = pushType
        self.messageId = messageId
        self.token = token
    }
}


extension IRCMessenger {
    
    public func reconnect() async throws {}
    
    public func disconnect() async throws {}
    
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func sendMessageReceivedReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {}
    
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
    public func sendMessage(_
                            message: RatchetedCypherMessage,
                            toUser username: Username,
                            otherUserDeviceId deviceId: DeviceId,
                            pushType: PushType,
                            messageId: String
    ) async throws {
        let body = IRCCypherMessage(message: message, pushType: pushType, messageId: messageId, token: self.makeToken())
        let data = try BSONEncoder().encode(body).makeData()
        do {
            let recipient = try await recipient(name: "\(username.raw)")
            _ = try await services?.sendMessage(data, to: recipient, tags: [
                IRCTags(key: "senderDeviceId", value: "\(self.deviceId)"),
                IRCTags(key: "recipientDeviceId", value: "\(deviceId)")
            ])
        } catch {
            print(error)
        }
    }
    
    public func recipient(name: String) async throws -> IRCMessageRecipient {
        switch type {
        case .channel:
            guard let name = IRCChannelName(name) else { throw IRCClientError.nilChannelName }
            return .channel(name)
        case .im:
            print(name)
            guard let validatedName = IRCNickName(name) else { throw IRCClientError.nilNickName }
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



public struct UserDeviceId: Hashable, Codable {
    let user: Username
    let device: DeviceId
}

struct Token: JWTPayload {
    let device: UserDeviceId
    let exp: ExpirationClaim
    
    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}
