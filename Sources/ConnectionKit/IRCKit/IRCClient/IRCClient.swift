import ArgumentParser
import Foundation
import NIO
import NIOTransportServices
import NIOIRC



internal class IRCClient: Identifiable {
    
    #if canImport(Network)
    public var niotsHandler: IRCNIOHandler?
    #endif
    public var delegate  : IRCClientDelegate?
    public  var id                  : UUID { account.id }
    public  let Q                   = DispatchQueue.main
    public  let account             : IRCAccount
    public  let passwordProvider    : IRCServicePasswordProvider
    
    private var activeClientOptions : IRCClientOptions?
    
    internal(set) public var conversations : [ String: IRCConversation ] = [:]
    internal(set) public var messageOfTheDay : String = ""
    
    internal struct NoNetworkFrameworkError: Swift.Error {}
    
    internal(set) public var state : State = .suspended {
        didSet {
            guard oldValue != state else { return }
            switch state {
            case .connecting: break
            case .online:
                conversations.values.forEach { $0.serviceDidGoOnline() }
            case .suspended, .offline:
                conversations.values.forEach { $0.serviceDidGoOffline() }
            }
        }
    }
    
    public enum State: Equatable {
        case suspended
        case offline
        case connecting(IRCNIOHandler)
        case online    (IRCNIOHandler)
    }
    
    
    public init(
        account: IRCAccount,
        passwordProvider: IRCServicePasswordProvider
    ) {
        self.account = account
        self.passwordProvider = passwordProvider
        self.activeClientOptions = self.clientOptionsForAccount(account)
        
        var group: EventLoopGroup? = nil
        #if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            group = NIOTSEventLoopGroup()
        } else {
            print("Sorry, your OS is too old for Network.framework.")
            exit(0)
        }
        #else
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        #endif
        
        
        defer {
            try? group?.syncShutdownGracefully()
        }
        
        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        
        #if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            guard let options = self.activeClientOptions else { return }
            self.niotsHandler = IRCNIOHandler(options: options, groupProvider: provider, group: group)
            self.niotsHandler?.delegate = self
        }
        #else
        
        #endif
    }
    
    deinit {
        
    }
    
    
    // MARK: - Connection
    private func handleAccountChange() {
        // TODO: integrate, reconnect if necessary
        connectIfNecessary()
    }
    
    private func connectIfNecessary() {
        guard case .offline = state else { return }
        state = .connecting(self.niotsHandler!)
        self.niotsHandler?.connect()
    }
    
    
    private func clientOptionsForAccount(_ account: IRCAccount) -> IRCClientOptions? {
        guard let nick = IRCNickName(account.nickname) else { return nil }
        return IRCClientOptions(
            port: account.port,
            host: account.host,
            tls: account.tls,
            password: activeClientOptions?.password,
            nickname: nick,
            userInfo: nil
        )
    }
    
    // MARK: - Lifecycle
    public func resume() {
        guard case .suspended = state else { return }
        state = .offline
        connectIfNecessary()
    }
    public func suspend() {
        defer { state = .suspended }
        switch state {
        case .suspended, .offline:
            return
        case .connecting(let client), .online(let client):
            client.disconnect()
        }
    }
    
    
    
    // MARK: - Conversations
    public func conversationWithID(_ id: String) -> IRCConversation? {
        return conversations[id.lowercased()]
    }
    
    @discardableResult
    public func registerChannel(_ name: String) -> IRCConversation? {
        let id = name.lowercased()
        if let c = conversations[id] { return c }
        guard let c = IRCConversation(channel: name, service: self) else { return nil }
        conversations[id] = c
        return c
    }
    public func unregisterChannel(_ name: String) {
        conversations.removeValue(forKey: name.lowercased())?.userDidLeaveChannel()
    }
    
    @discardableResult
    public func registerDirectMessage(_ name: String) -> IRCConversation? {
        let id = name.lowercased()
        if let c = conversations[id] { return c }
        guard let c = IRCConversation(nickname: name, service: self) else { return nil }
        conversations[id] = c
        return c
    }
    
    public func conversationsForRecipient(
        _ recipient: IRCMessageRecipient,
        create: Bool = false) -> [ IRCConversation ] {
        
        switch recipient {
        case .channel (let name):
            let id = name.stringValue.lowercased()
            if let c = conversations[id] { return [ c ] }
            guard create else { return [] }
            let new = IRCConversation(channel: name, service: self)
            conversations[id] = new
            return [ new ]
            
        case .nickname(let name):
            let id = name.stringValue.lowercased()
            if let c = conversations[id] { return [ c ] }
            guard create else { return [] }
            guard let new = IRCConversation(nickname: name.stringValue, service: self) else { return [] }
            conversations[id] = new
            return [ new ]
            
        case .everything:
            return Array(conversations.values)
        }
    }
    
    public func conversationsForRecipients(_ recipients: [ IRCMessageRecipient ],
                                           create: Bool = false) -> [ IRCConversation ] {
        var results = [ ObjectIdentifier : IRCConversation ]()
        for recipient in recipients {
            for conversation in conversationsForRecipient(recipient) {
                results[ObjectIdentifier(conversation)] = conversation
            }
        }
        return Array(results.values)
    }
    
    
    
    // MARK: - Sending
    @discardableResult
    public func sendMessage(_ message: String, to recipient: IRCMessageRecipient) -> Bool {
        guard case .online(let client) = state else { return false }
        client.sendMessage(message, to: recipient)
        return true
    }
}

