//
//  VideoKit.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore
import NIOTransportServices
import NIOPosix
import NIOIRC

final public class VideoKit: Identifiable {
    
    internal var elg                  : EventLoopGroup?
    public let mkAccount              : MKAccount
    private var activeClientOptions   : VideoClientOptions?
    internal var nioHandler           : NIOHandler?
    public let passwordProvider       : PasswordProvider
    internal(set) public var sessions : [ String: VideoSession ] = [:]
    
    internal var state : State = .suspended {
        didSet {
            guard oldValue != state else { return }
            switch state {
            case .connecting: break
            case .online:
                sessions.values.forEach { $0.serviceDidGoOnline() }
            case .suspended, .offline:
                sessions.values.forEach { $0.serviceDidGoOffline() }
            }
        }
    }
    
    internal enum State: Equatable {
        case suspended
        case offline
        case connecting(NIOHandler)
        case online    (NIOHandler)
    }
    
    public init(
        mkAccount: MKAccount,
        passwordProvider: PasswordProvider,
        elg: EventLoopGroup? = nil) {
        self.mkAccount = mkAccount
        self.passwordProvider = passwordProvider
        self.elg = elg
        self.activeClientOptions = self.clientOptionsForParticipant(self.mkAccount)
        
#if canImport(Network)
        if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            self.elg = NIOTSEventLoopGroup()
        } else {
            self.elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
#else
        self.elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        
        defer {
            try? self.elg?.syncShutdownGracefully()
        }
        
//        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        
        #if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            // Fire up NIO HANDLER
            guard let options = self.activeClientOptions else { return }
            self.nioHandler = NIOHandler(options: options, elg: self.elg!)
//            self.nioHandler?.delegate = self
        }
        #else
        
        #endif
    }
    
    private func handleAccountChange() {
        connectIfNecessary()
    }
    
    private func connectIfNecessary() {
        guard case .offline = state else { return }
        state = .connecting(self.nioHandler!)
        let promise = self.elg!.next().makePromise(of: Channel.self)
        let connected = self.nioHandler?.connect(promise: promise)
        connected?.whenFailure { error in
            promise.fail(error)
        }
    }
    
    private func clientOptionsForParticipant(_ mkAccount: MKAccount) -> VideoClientOptions? {
        guard let nick = IRCNickName(mkAccount.nickname) else { return nil }
        return VideoClientOptions(
            port: mkAccount.port,
            host: mkAccount.host,
            tls: mkAccount.tls,
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
    
    public func sessionWithId(_ id: String) -> VideoSession? {
        return sessions[id.lowercased()]
    }
    
    @discardableResult
    public func registerSession(_ name: String) -> VideoSession? {
        let id = name.lowercased()
        if let s = sessions[id] { return s }
        guard let s = VideoSession(serviceDelegate: self, groupSessionName: name) else { return nil }
        sessions[id] = s
        return s
    }
    
    public func unregisterSession(_ name: String) {
        sessions.removeValue(forKey: name.lowercased())?.userDidLeaveChannel()
    }
    
    @discardableResult
    public func registerPrivateSession(_ name: String) -> VideoSession? {
        let id = name.lowercased()
        if let s = sessions[id] { return s }
        guard let s = VideoSession(serviceDelegate: self, nickname: name) else { return nil }
        sessions[id] = s
        return s
    }
    
    public func sessionsForParticipant(_
                                        participant: IRCMessageRecipient,
                                        create: Bool = false
    ) -> [ VideoSession ] {
        switch participant {
        case .channel (let name):
            let id = name.stringValue.lowercased()
            if let c = sessions[id] { return [ c ] }
            guard create else { return [] }
            let new = VideoSession(serviceDelegate: self, groupSessionName: name)
            sessions[id] = new
            return [ new ]
            
        case .nickname(let name):
            let id = name.stringValue.lowercased()
            if let c = sessions[id] { return [ c ] }
            guard create else { return [] }
            guard let new = VideoSession(serviceDelegate: self, nickname: name.stringValue) else { return [] }
            sessions[id] = new
            return [ new ]
            
        case .everything:
            return Array(sessions.values)
        }
    }
    
    public func sessionsForParticipants(_
                                        participants: [ IRCMessageRecipient ],
                                        create: Bool = false
    ) -> [ VideoSession ] {
        var results = [ ObjectIdentifier: VideoSession]()
        for participant in participants {
            for session in sessionsForParticipant(participant) {
                results[ObjectIdentifier(session)] = session
            }
        }
        return Array(results.values)
    }
}

extension VideoKit: CustomStringConvertible {
    public var description: String { "<Service: \(mkAccount)>" }
}


