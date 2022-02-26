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
    
    public weak var delegate: CypherTransportClientDelegate?
    public private(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = false
    public var type : ConversationType = .im
    private let deviceId: DeviceId
    private(set) var signer: TransportCreationRequest
    private let username: Username
    private let appleToken: String?
    private let registrationType: RegistrationType?
    public var services: IRCService?
    internal var group: EventLoopGroup
    private var passwordProvider: String
    private var userState: UserState
    private var clientOptions: ClientOptions?
    public var store: NeedleTailStore
    internal var messenger: CypherMessenger?
    private var keyBundle: String = ""
    
    
    public init(
        passwordProvider: String,
        host: String,
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        appleToken: String?,
        messenger: CypherMessenger?,
        userState: UserState,
        clientOptions: ClientOptions?,
        store: NeedleTailStore,
        registrationType: RegistrationType?
    ) async throws {
#if canImport(Network)
        let group = NIOTSEventLoopGroup()
#else
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        self.group = group
        self.passwordProvider = passwordProvider
        self.userState = userState
        self.clientOptions = clientOptions
        self.store = store
        self.username = username
        self.deviceId = deviceId
        self.signer = signer
        self.appleToken = appleToken
        self.registrationType = registrationType
        
        self.services = await IRCService(
            signer: self.signer,
            passwordProvider: clientOptions?.password ?? "",
            authenticated: self.authenticated,
            userState: self.userState,
            clientOptions: clientOptions,
            delegate: self.delegate,
            store: self.store
        )
    }
    
    public class func authenticate(
        appleToken: String? = "",
        transportRequest: TransportCreationRequest,
        host: String,
        messenger: CypherMessenger? = nil,
        eventLoop: EventLoop,
        options: ClientOptions?,
        store: NeedleTailStore,
        registrationType: RegistrationType? = nil
    ) async throws -> IRCMessenger {
        return try await IRCMessenger(
            passwordProvider: options?.password ?? "",
            host: host,
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest,
            appleToken: appleToken,
            messenger: messenger,
            userState: UserState(identifier: ""),
            clientOptions: options,
            store: store,
            registrationType: registrationType
        )
    }
    
    //Publish, register, and  read nned to makeToken()
    public func registerBundle() async throws {
        //If we do not have a registration type, don't register
        switch registrationType {
        case .siwa:
            guard let appleToken = appleToken else { return }
            let siwaObject = siwaRequest(with: appleToken)
            let packet = try BSONEncoder().encode(siwaObject).makeData().base64EncodedString()
            await services?.resume(packet)
        case .plain:
            let plainObject = plainRequest()
            let packet = try BSONEncoder().encode(plainObject).makeData().base64EncodedString()
            await services?.resume(packet)
        case .none:
            break
        }
    }
    
    public func publishKeyBundle(_ data: UserConfig) async throws {
        guard let jwt = makeToken() else { throw IRCClientError.nilToken }
        let configObject = configRequest(jwt, config: data)
        self.keyBundle = try BSONEncoder().encode(configObject).makeData().base64EncodedString()
        await self.services?.client?.publishKeyBundle(self.keyBundle)
    }
    
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        guard let jwt = makeToken() else { throw IRCClientError.nilToken }
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        guard let userConfig = await services?.readKeyBundle(packet) else { throw IRCClientError.nilUsedConfig }
        return userConfig
    }
    
    public func registerAPNSToken(_ token: Data) async throws {
        guard let jwt = makeToken() else { return }
        let apnObject = apnRequest(jwt, appleToken: token.hexString, deviceId: self.deviceId)
        let packet = try BSONEncoder().encode(apnObject).makeData().base64EncodedString()
        await self.services?.registerAPN(packet)
    }
    
    private func makeToken() -> String? {
        return try? JWTSigner(algorithm: signer).sign(
            Token(
                device: UserDeviceId(user: self.username, device: self.deviceId),
                exp: .init(value: Date().addingTimeInterval(3600))
            )
        )
    }
    
    public func resumeIRC(signer: TransportCreationRequest) async {
        self.services = await IRCService(
            signer: signer,
            passwordProvider: self.passwordProvider,
            authenticated: self.authenticated,
            userState: self.userState,
            clientOptions: self.clientOptions,
            delegate: self.delegate,
            store: self.store
        )
        await self.resume()
    }
    
    
    internal func siwaRequest(with appleToken: String) -> SIWARequest {
        return SIWARequest(
            username: signer.username,
            appleToken: appleToken,
            config: signer.userConfig,
            deviceId: signer.deviceId
        )
    }
    
    internal func plainRequest() -> PlainSignUpRequest {
        return PlainSignUpRequest(
            username: signer.username,
            config: signer.userConfig,
            deviceId: signer.deviceId
        )
    }
    
    private func configRequest(_ jwt: String, config: UserConfig) -> UserConfigRequest {
        return UserConfigRequest(
            jwt: jwt,
            username: self.username,
            config: config,
            deviceId: self.deviceId
        )
    }
    
    private func apnRequest(_
                            jwt: String,
                            appleToken: String,
                            deviceId: DeviceId
    ) -> APNTokenRequest {
        return APNTokenRequest(jwt: jwt, appleToken: appleToken, username: self.username, deviceId: deviceId)
    }
    
    private func readBundleRequest(_ jwt: String, recipient: Username) -> ReadBundleRequest {
        ReadBundleRequest(jwt: jwt, sender: self.username, recipient: recipient, deviceId: self.deviceId)
    }
    
    struct SIWARequest: Codable {
        let username: Username
        let appleToken: String
        let config: UserConfig
        let deviceId: DeviceId
    }
    
    struct PlainSignUpRequest: Codable {
        let username: Username
        let config: UserConfig
        let deviceId: DeviceId
    }
    
    struct UserConfigRequest: Codable {
        let jwt: String
        let username: Username
        let config: UserConfig
        let deviceId: DeviceId
    }
    
    struct APNTokenRequest: Codable {
        let jwt: String
        let appleToken: String
        let username: Username
        let deviceId: DeviceId
    }
    
    struct ReadBundleRequest: Codable {
        let jwt: String
        let sender: Username
        let recipient: Username
        let deviceId: DeviceId
    }
    
    struct SignUpResponse: Codable {
        let existingUser: Username?
    }
    
    
    // MARK: - Service Lookup
    internal func serviceWithID(_ id: UUID) -> IRCService? {
        return services
    }
    
    internal func serviceWithID(_ id: String) -> IRCService? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return serviceWithID(uuid)
    }
    
    public func removeAccountWithID(_ id: UUID) {
        
    }
    
    // MARK: - Lifecycle
    public func resume() async {
        await services?.resume()
    }
    
    public func suspend() async {
        await services?.suspend()
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
    public func setDelegate(to delegate: CypherTransportClientDelegate) async throws {
        self.delegate = delegate
    }
    
    public func reconnect() async throws {}
    
    public func disconnect() async throws {}
    
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func sendMessageReceivedReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {}
    
    public struct SetToken: Codable {
        let token: String
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
            guard let name = IRCChannelName(name) else { throw ConnectionKitErrors.nilIRCChannelName }
            return .channel(name)
        case .im:
            print(name)
            guard let validatedName = IRCNickName(name) else { throw ConnectionKitErrors.nilIRCNickName }
            return .nickname(validatedName)
        }
    }
    
    public func sendMultiRecipientMessage(_ message: MultiRecipientCypherMessage, pushType: PushType, messageId: String) async throws {
        fatalError("There was an error!!!!!")
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
