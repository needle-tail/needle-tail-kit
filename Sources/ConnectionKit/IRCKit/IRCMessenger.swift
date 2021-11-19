//
//  IRCMessenger.swift
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


public class IRCMessenger: VaporClient, IRCMessageDelegate {

    
    func passSendMessage(_ text: String, to recipients: IRCMessageRecipient) {
        services?.sendMessage(text, to: recipients)
    }
    
    
//    public var services : [ IRCService ] = []
    public var services : IRCService?
    internal var group    : EventLoopGroup
    private var passwordProvider: String
//    private (set) public var accounts: [ IRCAccount ] = []
    
    
    
    
    public init(
        passwordProvider: String,
        host: String,
        username: Username,
        deviceId: DeviceId,
        signer: TransportCreationRequest,
        httpClient: URLSession,
        appleToken: String?
    ) async {
        let group = NIOTSEventLoopGroup()
        self.group = group
        self.passwordProvider = passwordProvider
        await super.init(host: host, username: username, deviceId: deviceId, signer: signer, httpClient: httpClient, appleToken: appleToken)
        
        await resumeIRC(signer: signer)
    }
    
    
    
    public func resumeIRC(signer: TransportCreationRequest) async {
        self.services = await IRCService(
            signer: signer,
            passwordProvider: self.passwordProvider,
            eventLoopGroup: self.group,
            authenticated: self.authenticated
        )
        
        
        
//        self.services = await self.accounts.asyncCompactMap({ account in
//            return await IRCService(account: account, passwordProvider: self.passwordProvider! as! IRCServicePasswordProvider, eventLoopGroup: self.group)
//        })
        
        
        self.resume()
    }
    
    
    // MARK: - Service Lookup
    internal func serviceWithID(_ id: UUID) -> IRCService? {
//        return services.first(where: { UUID(uuidString: $0.signer.deviceId.id) == id })
        return services
    }
    
    internal func serviceWithID(_ id: String) -> IRCService? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return serviceWithID(uuid)
    }
    
//    Adds an additional account to a service
//        public func addAccount(_ account: IRCAccountModel) async throws {
//            guard services.first(where: { $0.account.id == account.id }) == nil else {
//                assertionFailure("duplicate ID!")
//                return
//            }
//            let additionalAccount = IRCAccount(databaseEncryptionKey: self.databaseEncryptionKey, model: try await messenger.decrypt(account))
//            let service = await IRCService(account: additionalAccount, passwordProvider: self.passwordProvider, eventLoopGroup: self.group, messenger: messenger)
//            services.append(service)
//
//    //        persistAccounts()
//        }
    
    public func removeAccountWithID(_ id: UUID) {
//        guard let idx = services.firstIndex(where: { UUID(uuidString: $0.signer.deviceId.id) == id }) else { return }
//        services.remove(at: idx)
        //        persistAccounts()
    }
    
    //    private func persistAccounts() {
    //        do {
    //            try defaults.encode(services.map(\.account), forKey: .accounts)
    //        }
    //        catch {
    //            assertionFailure("Could not persist accounts: \(error)")
    //            print("failed to persist accounts:", error)
    //        }
    //    }
    
    
    // MARK: - Lifecycle
    
    public func resume() {
        services?.resume()
//        services.forEach { $0.resume() }
    }
    public func suspend() {
        services?.suspend()
//        services.forEach { $0.suspend() }
    }
}



struct IRCCypherMessage<Message: Codable>: Codable {
    var message: Message
    var pushType: PushType
    var messageId: String
    
    init(
        message: Message,
        pushType: PushType,
        messageId: String
    ) {
        self.message = message
        self.pushType = pushType
        self.messageId = messageId
    }
}
