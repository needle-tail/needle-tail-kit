import ArgumentParser
import Foundation
import NIO
import NIOTransportServices
import NIOIRC
import CypherMessaging
import Crypto
import IRC

public final class IRCService: Identifiable, Hashable, IRCServiceDelegate {
    
    
    public enum IRCServiceState: Equatable {
        
        case suspended
        case offline
        case connecting(IRCClient)
        case online    (IRCClient)
    }
    
    public static func == (lhs: IRCService, rhs: IRCService) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
    internal var store: ConnectionKitIRCStore?
    public var id: UUID { UUID(uuidString: signer.deviceId.id)! }
    public let signer: TransportCreationRequest
    public let eventLoopGroup: EventLoopGroup
    public let passwordProvider: String
    private var activeClientOptions: IRCClientOptions?
    private (set) public var conversations: [ IRCConversation ] = []
    private var convs: [IRCConversationModel]?
    private var authenticated: AuthenticationState?
    let databaseEncryptionKey = SymmetricKey(data: Data())
    public var delegate : IRCClientDelegate?
    
    private(set) public var ircServiceState : IRCServiceState = .suspended {
        didSet {
            guard oldValue != ircServiceState else { return }
            switch ircServiceState {
            case .connecting: break
            case .online:
                conversations.forEach { c in
                    Task {
                        await c.serviceDidGoOnline()
                    }
                }
            case .suspended, .offline:
                conversations.forEach { c in
                    Task {
                        await c.serviceDidGoOffline()
                    }
                }
            }
        }
    }
    
    
    public init(
        signer: TransportCreationRequest,
        passwordProvider: String,
        eventLoopGroup: EventLoopGroup,
        authenticated: AuthenticationState
    )
    async {
        self.eventLoopGroup = eventLoopGroup
        self.passwordProvider = passwordProvider
        self.signer = signer
        self.authenticated = authenticated
        
        
        //        do {
        //        self.conversations = try await fetchConversations()
        //        } catch {
        //            print(error)
        //        }
        //      self.accountSubscriber = account.objectWillChange.sink {
        //        [weak self] in self?.handleAccountChange()
        //      }
        
        activeClientOptions = clientOptionsForAccount(signer)
    }
    
    func fetchConversationModel() async -> [IRCConversationModel] {
        if let conv = self.convs {
            return conv
        } else {
            let contacts = try? await self.store?.fetchConversations()
            self.convs = contacts
            return contacts!
        }
        
    }
    
    //    public func fetchConversations() async throws -> [IRCConversation] {
    //        try await self.fetchConversationModel().asyncMap { conversation in
    //            return IRCConversation(databaseEncryptionKey: databaseEncryptionKey, model: try await messenger.decrypt(conversation), service: self)
    //        }
    //    }
    
    //    public let model: DecryptedModel<IRCServiceModel>
    
    // MARK: - Connection
    private func handleAccountChange() {
        // TODO: integrate, reconnect if necessary
        self.connectIfNecessary()
    }
    
    private func connectIfNecessary() {
        guard case .offline = ircServiceState else { return }
        guard let options = activeClientOptions else { return }
        let client = IRCClient(options: options)
        client.delegate = self
        ircServiceState = .connecting(client)

        do {
        let channel = try client.connecting()
            channel.whenComplete { switch $0 {
            case .success(let channel):
                print(channel)
                self.authenticated = .authenticated
            case .failure(let error):
                self.eventLoopGroup.next().execute {
                    self.connectIfNecessary()
                }
                print(error)
            }}
        } catch {
            self.authenticated = .authenticationFailure
            print(error, "OUR ERROR")
        }
        
    }
    
    
    private func clientOptionsForAccount(_ signer: TransportCreationRequest) -> IRCClientOptions? {
        guard let nick = IRCNickName(signer.username.raw) else { return nil }
        return IRCClientOptions(
            port: 6667,
            host: "localhost",
            password: activeClientOptions?.password,
            tls: false,
            nickname: nick,
            userInfo: nil
        )
    }
    
    // MARK: - Lifecycle
    public func resume() {
        guard case .suspended = ircServiceState else { return }
        ircServiceState = .offline
        connectIfNecessary()
    }
    
    
    public func suspend() {
        defer { ircServiceState = .suspended }
        switch ircServiceState {
        case .suspended, .offline:
            return
        case .connecting(let client), .online(let client):
            client.disconnect()
        }
    }
    
    
    
    // MARK: - Conversations
    public func conversationWithID(_ id: String) -> IRCConversation? {
        let conversation = conversations.first { $0.id?.uuidString == id }
        return conversation
    }
    
    
    
    
    @discardableResult
    public func registerChannel(_ name: String) async throws -> IRCConversation? {
        let id = name.lowercased()
        let conversation = conversations.first { $0.id?.uuidString == id }
        if let c = conversation { return c }
        
        guard let conv = IRCConversationModel.SecureProps(
            channel: name,
            metadata: [:]
        ) else { throw IRCClientError.nilSecureProps }
        let c = try? await self.store?.createConversation(IRCConversationModel(props: conv, encryptionKey: self.databaseEncryptionKey))
        return c
    }
    
    
    public func unregisterChannel(_ name: String) {
        //        conversations.removeValue(forKey: name.lowercased())?.userDidLeaveChannel()
    }
    
    @discardableResult
    public func registerDirectMessage(_ name: String) async throws -> IRCConversation? {
        let channel = name.lowercased()
        guard let conv = IRCConversationModel.SecureProps(
            channel: channel,
            metadata: [:]
        ) else { throw IRCClientError.nilSecureProps }
        let c = try? await self.store?.createConversation(IRCConversationModel(props: conv, encryptionKey: self.databaseEncryptionKey))
        return c
    }
    
    public func conversationsForRecipient(
        _ recipient: IRCMessageRecipient,
        create: Bool = false) async throws -> [ IRCConversation ] {
            
            switch recipient {
            case .channel (let name):
                let id = name.stringValue.lowercased()
                let conversation = conversations.first { $0.id?.uuidString == id }
                guard let c = conversation else {
                    throw IRCClientError.nilConversation
                }
                guard create else { return [c] }
                
                let conv = IRCConversationModel.SecureProps(
                    channel: name,
                    metadata: [:]
                )
                guard let new = try? await self.store?.createConversation(IRCConversationModel(props: conv, encryptionKey: self.databaseEncryptionKey)) else { throw IRCClientError.nilConversation }
                //            let new = IRCConversation(channel: name, service: self)
                //            conversations[id] = new
                return [ new ]
                
            case .nickname(let name):
                let id = name.stringValue.lowercased()
                let conversation = conversations.first { $0.id?.uuidString == id }
                if let c = conversation { return [ c ] }
                guard create else { return [] }
                guard let conv = IRCConversationModel.SecureProps(
                    channel: name.stringValue,
                    metadata: [:]
                ) else { throw IRCClientError.nilSecureProps }
                guard let new = try? await self.store?.createConversation(IRCConversationModel(props: conv, encryptionKey: self.databaseEncryptionKey)) else { throw IRCClientError.nilConversation }
                //            guard let new = IRCConversation(nickname: name.stringValue, service: self) else { return [] }
                //            conversations[id] = new
                return [ new ]
                
            case .everything:
                return Array(conversations)
            }
        }
    
    public func conversationsForRecipients(_ recipients: [ IRCMessageRecipient ],
                                           create: Bool = false) async -> [ IRCConversation ] {
        var results = [ ObjectIdentifier : IRCConversation ]()
        
        
        for recipient in recipients {
            _ = try? await self.conversationsForRecipient(recipient).compactMap({ c in
                results[ObjectIdentifier(c.model)]  = c
            })
        }
        return Array(results.values)
    }
    
    
    
    // MARK: - Sending
    @discardableResult
    public func sendMessage(_ message: String, to recipient: IRCMessageRecipient) -> Bool {
        guard case .online(let client) = ircServiceState else { return false }
        client.sendMessage(message, to: recipient)
        return true
    }
}



extension IRCService: IRCClientDelegate {
    
    // MARK: - Messages
    
    public func client(_       client : IRCClient,
                       notice message : String,
                       for recipients : [ IRCMessageRecipient ]) async {
        self.updateConnectedClientState(client)
        
        // FIXME: this is not quite right, mirror what we do in message
        _ = await self.conversationsForRecipients(recipients)
            .asyncCompactMap({ conversation in
                await conversation.addNotice(message)
            })
    }
    public func client(_       client : IRCClient,
                       message        : String,
                       from    sender : IRCUserID,
                       for recipients : [ IRCMessageRecipient ]) async
    {
        self.updateConnectedClientState(client)
        
        // FIXME: We need this because for DMs we use the sender as the
        //        name
        for recipient in recipients {
            switch recipient {
            case .channel(let name):
                if let c = try? await self.registerChannel(name.stringValue) {
                    await c.addMessage(message, from: sender)
                }
            case .nickname: // name should be us
                if let c = try? await self.registerDirectMessage(sender.nick.stringValue) {
                    await c.addMessage(message, from: sender)
                }
            case .everything:
                
                _ = await conversations.asyncCompactMap({ conversation in
                    await conversation.addMessage(message, from: sender)
                })
            }
        }
    }
    
    public func client(_ client: IRCClient, messageOfTheDay message: String) async {
        self.updateConnectedClientState(client)
        
        //            self.messageOfTheDay = message
    }
    
    
    // MARK: - Channels
    
    public func client(_ client: IRCClient,
                       user: IRCUserID, joined channels: [ IRCChannelName ]) async
    {
        self.updateConnectedClientState(client)
        
        _ = await channels.asyncCompactMap({ channel in
            try? await self.registerChannel(channel.stringValue)
        })
    }
    
    public func client(_ client: IRCClient,
                       user: IRCUserID, left channels: [ IRCChannelName ],
                       with message: String?) async
    {
        self.updateConnectedClientState(client)
        channels.forEach { self.unregisterChannel($0.stringValue) }
    }
    
    public func client(_ client: IRCClient,
                       changeTopic welcome: String, of channel: IRCChannelName) async
    {
        self.updateConnectedClientState(client)
        // TODO: operation
    }
    
    
    // MARK: - Connection
    
    /**
     * Bring the service online if necessary, update derived properties.
     * This is called by all methods that signal connectivity.
     */
    private func updateConnectedClientState(_ client: IRCClient) {
        switch self.ircServiceState {
        case .offline, .suspended:
            assertionFailure("not connecting, still getting connected client info")
            return
            
        case .connecting(let ownClient):
            guard client === ownClient else {
                assertionFailure("client mismatch")
                return
            }
            print("going online:", client)
            self.ircServiceState = .online(client)
            
            //            let channels = account.joinedChannels.compactMap(IRCChannelName.init)
            
            // TBD: looks weird. doJoin is for replies?
            //            client.sendMessage(.init(command: .JOIN(channels: channels, keys: nil)))
            
        case .online(let ownClient):
            guard client === ownClient else {
                assertionFailure("client mismatch")
                return
            }
            // TODO: update state (nick, userinfo, etc)
        }
    }
    
    public func client(_ client        : IRCClient,
                       registered nick : IRCNickName,
                       with   userInfo : IRCUserInfo) async {
        self.updateConnectedClientState(client)
    }
    public func client(_ client: IRCClient, changedNickTo nick: IRCNickName) async {
        self.updateConnectedClientState(client)
    }
    public func client(_ client: IRCClient, changedUserModeTo mode: IRCUserMode) async {
        self.updateConnectedClientState(client)
    }
    
    public func clientFailedToRegister(_ newClient: IRCClient) async {
        switch self.ircServiceState {
        case .offline, .suspended:
            assertionFailure("not connecting, still get registration failure")
            return
            
        case .connecting(let ownClient), .online(let ownClient):
            guard newClient === ownClient else {
                assertionFailure("client mismatch")
                return
            }
            
            print("Closing client ...")
            ownClient.delegate = nil
            self.ircServiceState = .offline
            ownClient.disconnect()
        }
    }
}

extension IRCClient: Equatable {
    public static func == (lhs: IRCClient, rhs: IRCClient) -> Bool {
        return lhs === rhs
    }
}



//
//public class IRCService: Identifiable, Hashable, Codable {
//    
//    public var delegate  : IRCClientDelegate?
//    public  var id                  : UUID
//    public  let Q                   = DispatchQueue.main
//    public  let account             : IRCAccountModel
//    public  let passwordProvider    : IRCServicePasswordProvider
//    
//    private var activeClientOptions : IRCClientOptions?
//    internal var group              : EventLoopGroup?
//    internal(set) public var conversations : [ String: IRCConversationModel ] = [:]
//    internal(set) public var messageOfTheDay : String = ""
//
//    internal struct NoNetworkFrameworkError: Swift.Error {}
//    
//    internal(set) public var state : State = .suspended {
//        didSet {
//            guard oldValue != state else { return }
//            switch state {
//            case .connecting: break
//            case .online:
//                conversations.values.forEach { $0.serviceDidGoOnline() }
//            case .suspended, .offline:
//                conversations.values.forEach { $0.serviceDidGoOffline() }
//            }
//        }
//    }
//    
//    public enum State: Equatable {
//        case suspended
//        case offline
//        case connecting(IRCClient)
//        case online    (IRCClient)
//    }
//
//
//    
//    public init(
//        account: IRCAccountModel,
//        passwordProvider: IRCServicePasswordProvider,
//        group: EventLoopGroup? = nil
//    ) {
//        self.id = account.id
//        self.account = account
//        self.passwordProvider = passwordProvider
//        self.group = group
//        self.activeClientOptions = self.clientOptionsForAccount(account)
//
//    }
//    
//      
//      
//      
//      
//      public static func == (lhs: IRCService, rhs:  IRCService) -> Bool {
//          return lhs.account.id == rhs.account.id
//      }
//
//      public func hash(into hasher: inout Hasher) {
//          hasher.combine(account.id)
//      }
//
//      
//    
//    
//    deinit {
//        
//    }
//    
//    
//    // MARK: - Connection
//    private func handleAccountChange() {
//        // TODO: integrate, reconnect if necessary
//        connectIfNecessary()
//    }
//    
//    private func connectIfNecessary() {
//        guard case .offline = state else { return }
//        guard let options = activeClientOptions else { return }
//        let client = IRCClient(options: options)
//        client.delegate = self
//        state = .connecting(client)
//        client.connecting()
//    }
//    
//    
//    private func clientOptionsForAccount(_ account: IRCAccountModel) -> IRCClientOptions? {
//        guard let nick = IRCNickName(account.id.uuidString) else { return nil }
//        return IRCClientOptions(
//            port: account.port,
//            host: account.host,
//            tls: account.tls,
//            password: activeClientOptions?.password,
//            nickname: nick,
//            userInfo: nil
//        )
//    }
//    
//    // MARK: - Lifecycle
//    public func resume() {
//        guard case .suspended = state else { return }
//        state = .offline
//        connectIfNecessary()
//    }
//    public func suspend() {
//        defer { state = .suspended }
//        switch state {
//        case .suspended, .offline:
//            return
//        case .connecting(let client), .online(let client):
//            client.disconnect()
//        }
//    }
//    
//    
//    
//    // MARK: - Conversations
//    public func conversationWithID(_ id: String) -> IRCConversationModel? {
//        return conversations[id.lowercased()]
//    }
//    
//    @discardableResult
//    public func registerChannel(_ name: String) -> IRCConversationModel? {
//        let id = name.lowercased()
//        if let c = conversations[id] { return c }
//        guard let c = IRCConversationModel(channel: name, service: self) else { return nil }
//        conversations[id] = c
//        return c
//    }
//    public func unregisterChannel(_ name: String) {
//        conversations.removeValue(forKey: name.lowercased())?.userDidLeaveChannel()
//    }
//    
//    @discardableResult
//    public func registerDirectMessage(_ name: String) -> IRCConversationModel? {
//        let id = name.lowercased()
//        if let c = conversations[id] { return c }
//        guard let c = IRCConversationModel(nickname: name, service: self) else { return nil }
//        conversations[id] = c
//        return c
//    }
//    
//    public func conversationsForRecipient(
//        _ recipient: IRCMessageRecipient,
//        create: Bool = false) -> [ IRCConversationModel ] {
//        
//        switch recipient {
//        case .channel (let name):
//            let id = name.stringValue.lowercased()
//            if let c = conversations[id] { return [ c ] }
//            guard create else { return [] }
//            let new = IRCConversationModel(channel: name, service: self)
//            conversations[id] = new
//            return [ new ]
//            
//        case .nickname(let name):
//            let id = name.stringValue.lowercased()
//            if let c = conversations[id] { return [ c ] }
//            guard create else { return [] }
//            guard let new = IRCConversationModel(nickname: name.stringValue, service: self) else { return [] }
//            conversations[id] = new
//            return [ new ]
//            
//        case .everything:
//            return Array(conversations.values)
//        }
//    }
//    
//    public func conversationsForRecipients(_ recipients: [ IRCMessageRecipient ],
//                                           create: Bool = false) -> [ IRCConversationModel ] {
//        var results = [ ObjectIdentifier : IRCConversationModel ]()
//        for recipient in recipients {
//            for conversation in conversationsForRecipient(recipient) {
//                results[ObjectIdentifier(conversation)] = conversation
//            }
//        }
//        return Array(results.values)
//    }
//    
//    
//    
//    // MARK: - Sending
//    @discardableResult
//    public func sendMessage(_ message: String, to recipient: IRCMessageRecipient) -> Bool {
//        guard case .online(let client) = state else { return false }
//        client.sendMessage(message, to: recipient)
//        return true
//    }
//}
//
