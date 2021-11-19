//
//  VaporClient.swift
//
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIOCore
import NIOTransportServices
import CypherMessaging
import CypherProtocol
import Crypto
import NIOIRC
import MessagingHelpers
import BSON
import JWTKit


public class VaporClient: CypherServerTransportClient {
    
    
    public var delegate: CypherTransportClientDelegate?
    public private(set) var authenticated = AuthenticationState.unauthenticated
    public var supportsMultiRecipientMessages = true
    internal var ircMessageDelegate: IRCMessageDelegate?
    
    static var host: String = ""
    let username: Username
    let httpClient: URLSession
    let deviceId: DeviceId
    var httpHost: String { "https://\(String(describing: VaporClient.host))" }
    var appleToken: String?
    private(set) var signer: TransportCreationRequest
    
    internal init(
        host: String,
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        httpClient: URLSession,
        appleToken: String?
    ) async {
        VaporClient.host = host
        self.username = username
        self.deviceId = deviceId
        self.httpClient = httpClient
        self.signer = signer
    }
    
    public class func login(for transportRequest: TransportCreationRequest, host: String) async throws -> IRCMessenger {
        let client = URLSession(configuration: .default)
        VaporClient.host = Self.host
        return await IRCMessenger(
            passwordProvider: "",
            host: host,
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest,
            httpClient: client,
            appleToken: nil
        )
    }
    
    
    public class func register(
        appleToken: String,
        transportRequest: TransportCreationRequest,
        host: String,
        eventLoop: EventLoop
    ) async throws -> VaporClient {
        let client = URLSession(configuration: .default)
        let request = SIWARequest(
            username: transportRequest.username.raw,
            appleToken: appleToken,
            config: transportRequest.userConfig
        )
        let transport = await VaporClient(
            host: host,
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest,
            httpClient: client,
            appleToken: appleToken
        )
        
        let (body) = try await client.codableNetworkWrapper(
            type: SIWARequest.self,
            httpHost: transport.httpHost,
            urlPath: "auth/siwa/register",
            httpMethod: "POST",
            httpBody: request,
            username: transport.username,
            deviceId: transport.deviceId
        )
       
        let signUpResponse = try BSONDecoder().decode(SignUpResponse.self, from: Document(data: body.0))
        
        if let existingUser = signUpResponse.existingUser, existingUser != transportRequest.username {
            throw VaporClientErrors.usernameMismatch
        }
        
        return transport
    }
    
    public static func registerPlain(
        transportRequest: TransportCreationRequest,
        host: String,
        eventLoop: EventLoop
    ) async throws -> VaporClient {
        let client = URLSession(configuration: .default)
        let request = PlainSignUpRequest(
            username: transportRequest.username.raw,
            config: transportRequest.userConfig
        )
        
        let transport = await VaporClient(
            host: host,
            username: transportRequest.username,
            deviceId: transportRequest.deviceId,
            signer: transportRequest, httpClient: client,
            appleToken: nil
        )
        
        let (body) = try await client.codableNetworkWrapper(
            type: PlainSignUpRequest.self,
            httpHost: transport.httpHost,
            urlPath: "auth/plain/register",
            httpMethod: "POST",
            httpBody: request,
            username: transport.username,
            deviceId: transport.deviceId
        )
            
        let signUpResponse = try BSONDecoder().decode(SignUpResponse.self, from: Document(data: body.0))
        
        if let existingUser = signUpResponse.existingUser, existingUser != transportRequest.username {
            throw VaporClientErrors.usernameMismatch
        }
        
        return transport
    }
    
    public func readKeyBundle(forUsername username: Username) async throws -> UserConfig {
        let body = try await self.httpClient.codableNetworkWrapper(
            type: UserConfig.self,
            httpHost: self.httpHost,
            urlPath: "auth/users/\(username.raw)",
            httpMethod: "GET",
            username: self.username,
            deviceId: self.deviceId,
            token: self.makeToken()
        )

        let profile = try BSONDecoder().decode(UserProfile.self, from: Document(data: body.0))
        return profile.config
        
    }
    
    private func makeToken() -> String? {
        return try? JWTSigner(algorithm: signer).sign(
            Token(
                device: UserDeviceId(user: self.username, device: self.deviceId),
                exp: .init(value: Date().addingTimeInterval(3600))
            )
        )
    }
    
    
    struct SIWARequest: Codable {
        let username: String
        let appleToken: String
        let config: UserConfig
    }
    
    struct PlainSignUpRequest: Codable {
        let username: String
        let config: UserConfig
    }
    
    struct SignUpResponse: Codable {
        let existingUser: Username?
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


enum VaporClientErrors: Error {
    case usernameMismatch
}


extension VaporClient {
    public func setDelegate(to delegate: CypherTransportClientDelegate) async throws {
        self.delegate = delegate
    }
    
    public func reconnect() async throws {}
    
    public func disconnect() async throws {}
    
    public func sendMessageReadReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func sendMessageReceivedReceipt(byRemoteId remoteId: String, to username: Username) async throws {}
    
    public func requestDeviceRegistery(_ config: UserDeviceConfig) async throws {}

    
    public func publishKeyBundle(_ data: UserConfig) async throws {
        _ = try await self.httpClient.codableNetworkWrapper(
            type: UserConfig.self,
            httpHost: httpHost,
            urlPath: "auth/current-user/config",
            httpMethod: "POST",
            httpBody: data,
            username: self.username,
            deviceId: self.deviceId,
            token: self.makeToken())
    }
    
//    public func registerAPNSToken(_ token: Data) async throws {
//        _ = try await self.httpClient.postBSON(
//            httpHost: httpHost,
//            url: "current-device/token",
//            username: self.username,
//            deviceId: self.deviceId,
//            token: self.makeToken(),
//            body: SetToken(token: token.hexString)
//        )
//    }
    
    public func publishBlob<C>(_ blob: C) async throws -> ReferencedBlob<C> where C : Decodable, C : Encodable {
        fatalError()
    }
    
    public func readPublishedBlob<C>(byId id: String, as type: C.Type) async throws -> ReferencedBlob<C>? where C : Decodable, C : Encodable {
        fatalError()
    }
    
    public func sendMessage(_ message: RatchetedCypherMessage, toUser username: Username, otherUserDeviceId: DeviceId, pushType: PushType, messageId: String) async throws {
        let body = IRCCypherMessage(message: message, pushType: pushType, messageId: messageId)
        let data = try BSONEncoder().encode(body).makeData()
        guard let stringData = String(data: data, encoding: .utf8) else { return }
        self.ircMessageDelegate?.passSendMessage(stringData, to: .nickname(IRCNickName(username.id)!))
        
    }
    
    public func sendMultiRecipientMessage(_ message: MultiRecipientCypherMessage, pushType: PushType, messageId: String) async throws {
        let body = IRCCypherMessage(message: message, pushType: pushType, messageId: messageId)
        let data = try BSONEncoder().encode(body).makeData()
        guard let stringData = String(data: data, encoding: .utf8) else { return }
        self.ircMessageDelegate?.passSendMessage(stringData, to: .channel(IRCChannelName("#SwiftDE")!))
    }
}

protocol IRCMessageDelegate {
    func passSendMessage(_ text: String, to recipients: IRCMessageRecipient)
}
