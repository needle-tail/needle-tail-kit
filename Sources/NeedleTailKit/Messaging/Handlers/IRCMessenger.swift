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
    private var userState: UserState
    private var clientOptions: ClientOptions?
    private var keyBundle: String = ""
    private var waitingToReadBundle: Bool = false
    var messenger: CypherMessenger?
    var services: IRCService?
    var logger: Logger
    var messageType = MessageType.message
    var readRecipect: ReadReceiptPacket?
    
    //Entry wrapper variables
    var ircMessenger: IRCMessenger?
    
    public init(
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        appleToken: String?,
        userState: UserState,
        clientOptions: ClientOptions?
    ) async throws {
        self.logger = Logger(label: "IRCMessenger - ")
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
            userState: UserState(identifier: UUID()),
            clientOptions: options
        )
    }
    
    
    public func startService(_ appleToken: String = "") async throws {
        if self.services == nil {
            self.services = await IRCService(
                signer: self.signer,
                authenticated: self.authenticated,
                userState: self.userState,
                clientOptions: clientOptions,
                delegate: self.delegate
            )
        }
        let regObject = regRequest(with: appleToken)
        let packet = try BSONEncoder().encode(regObject).makeData().base64EncodedString()
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
            try await self.startService(appleToken)
        case .none:
            break
        }
    }
    
    /// We only Publish Key Bundles when a user is adding mutli-devcie support.
    /// It's required to only allow publishing by devices whose identity matches that of a **master device**. The list of master devices is published in the user's key bundle.
    
    public func publishKeyBundle(_ data: UserConfig) async throws {
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }
        let configObject = configRequest(jwt, config: data)
        self.keyBundle = try BSONEncoder().encode(configObject).makeData().base64EncodedString()
        let recipient = try await recipient(name: "\(username.raw)")

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
        _ = await services?.client?.sendPrivateMessage(data, to: recipient, tags: nil)
    }
    
    /// When we initially create a user we need to read the key bundle upon registration. Since the User first is created on the Server a **UserConfig** exists.
    /// Therefore **CypherTextKit** will ask to read that users bundle. If It does not exist then the error is caught and we will call ``publishKeyBundle(_ data:)``
    /// from **CypherTextKit**'s **registerMessenger()** method.
    @KeyBundleActor
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        guard let jwt = makeToken() else { throw NeedleTailError.nilToken }

        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData().base64EncodedString()
        guard let services = services else { throw NeedleTailError.nilService }
        let date = RunLoop.timeInterval(10)
        var canRun = false
        
        var userConfig: UserConfig? = nil
        
        if !waitingToReadBundle {
            services.client?.acknowledgment = Acknowledgment.AckType.readKeyBundle("")
            repeat {
                canRun = true
                if services.client?.channel != nil {
                    userConfig = await services.client?.readKeyBundle(packet)
                    
                    canRun = false
                }
            } while await RunLoop.execute(date, ack: services.client?.acknowledgment, canRun: canRun)
            services.client?.acknowledgment = Acknowledgment.AckType.none
        } else {
            repeat {
                switch services.client?.acknowledgment {
                case .registered(let registered):
                    canRun = true
                    if Bool(registered) != nil {
                        userConfig = await services.client?.readKeyBundle(packet)
                        canRun = false
                    }
                    waitingToReadBundle = false
                default:
                    break
                }
            } while await RunLoop.execute(date, ack: services.client?.acknowledgment, canRun: canRun)
        }
        guard let userConfig = userConfig else { throw NeedleTailError.nilUserConfig }
        services.client?.acknowledgment = .none
        return userConfig
    }
    
    
    public func registerAPNSToken(_ token: Data) async throws {
        guard let jwt = makeToken() else { return }
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: self.deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData().base64EncodedString()
        let recipient = try await recipient(name: "\(username.raw)")
        
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
        _ = await services?.client?.sendPrivateMessage(data, to: recipient, tags: nil)
        
    }

    private func makeToken() -> String? {
        return try? JWTSigner(algorithm: signer as! JWTAlgorithm)
            .sign(
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
    
    @NeedleTailActor
    public func resume(_ regPacket: String? = nil) async {
        do {
            //TODO: State Error
            try await services?.attemptConnection(regPacket)
            self.authenticated = .authenticated
        } catch {
            self.authenticated = .authenticationFailure
            await resume(regPacket)
        }
    }
    
    @NeedleTailActor
    public func suspend(_ isSuspending: Bool = false) async {
        //TODO: State Error
        await services?.attemptDisconnect(isSuspending)
    }
}

public enum RegistrationType {
    case siwa, plain
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
    @NeedleTailActor
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
            let recipient = try await recipient(name: "\(ircUser)")
            await services?.client?.sendPrivateMessage(data, to: recipient, tags: [
                IRCTags(key: "senderDeviceId", value: "\(self.deviceId)"),
                IRCTags(key: "recipientDeviceId", value: "\(deviceId)")
            ])
        } catch {
            logger.error("\(error)")
        }
    }
    
    
    public func recipient(name: String) async throws -> IRCMessageRecipient {
        switch type {
        case .channel:
            guard let name = IRCChannelName(name) else { throw NeedleTailError.nilChannelName }
            return .channel(name)
        case .im:
            print(name)
            guard let validatedName = NeedleTailNick(name) else { throw NeedleTailError.nilNickName }
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
