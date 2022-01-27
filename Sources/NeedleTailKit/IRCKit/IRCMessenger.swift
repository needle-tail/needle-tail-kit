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

public class IRCMessenger: VaporClient, IRCMessageDelegate {
    
    func passSendMessage(_ text: Data, to recipients: IRCMessageRecipient, tags: [IRCTags]?) async {
        do {
            try await services?.sendMessage(text, to: recipients, tags: tags)
        } catch {
            print("There was an error error sendding message in \(#function) - Error: \(error)")
        }
    }
    
    public var services: IRCService?
    internal var group: EventLoopGroup
    private var passwordProvider: String
    private var userState: UserState
    private var clientOptions: ClientOptions?
    
    public init(
        passwordProvider: String,
        host: String,
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        httpClient: URLSession,
        appleToken: String?,
        messenger: CypherMessenger?,
        userState: UserState,
        clientOptions: ClientOptions?
    ) async {
        #if canImport(Network)
        let group = NIOTSEventLoopGroup()
        #else
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        #endif
        self.group = group
        self.passwordProvider = passwordProvider
        self.userState = userState
        self.clientOptions = clientOptions
        await super.init(host: host, username: username, deviceId: deviceId, signer: signer, httpClient: httpClient, appleToken: appleToken)
        messageDelegate = self
        await resumeIRC(signer: signer)
    }
    
    public func resumeIRC(signer: TransportCreationRequest) async {
        self.services = await IRCService(
            signer: signer,
            passwordProvider: self.passwordProvider,
            eventLoopGroup: self.group,
            authenticated: self.authenticated,
            userState: self.userState,
            clientOptions: self.clientOptions,
            delegate: self.delegate
        )
            await self.resume()
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
