////
////  VideoKit.swift
////  
////
////  Created by Cole M on 10/9/21.
////
//
//import Foundation
//import NIOCore
//import NIOTransportServices
//import NIOPosix
//import NIOIRC
//
//final public class VideoKit: Identifiable {
//    
//    internal var group                : EventLoopGroup?
//    public let ckAccount              : CKAccount
////    private var activeClientOptions   : VideoClientOptions?
////    internal var nioHandler           : UDPNIOHandler?
//    public let passwordProvider       : String
//    internal(set) public var sessions : [ String: VideoSession ] = [:]
//    
//    internal var state : State = .suspended {
//        didSet {
//            guard oldValue != state else { return }
//            switch state {
//            case .connecting: break
//            case .online:
//                sessions.values.forEach { $0.serviceDidGoOnline() }
//            case .suspended, .offline:
//                sessions.values.forEach { $0.serviceDidGoOffline() }
//            }
//        }
//    }
//    
//    internal enum State: Equatable {
//        case suspended
//        case offline
////        case connecting(UDPNIOHandler)
////        case online    (UDPNIOHandler)
//    }
//    
//    public init(
//        ckAccount: CKAccount,
//        passwordProvider: String,
//        group: EventLoopGroup? = nil) {
//            self.ckAccount = ckAccount
//            self.passwordProvider = passwordProvider
//            self.group = group
//            self.activeClientOptions = self.clientOptionsForParticipant(self.ckAccount)
//            
//            
//            if self.group == nil {
//#if canImport(Network)
//                if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
//                    self.group = NIOTSEventLoopGroup()
//                } else {
//                    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//                }
//#else
//                self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//#endif
//            }
//            
//            defer {
////                try? self.group?.syncShutdownGracefully()
//            }
//            
//            let provider: EventLoopGroupManager.Provider = self.group.map { .shared($0) } ?? .createNew
//            
//#if canImport(Network)
//            if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
//                guard let options = self.activeClientOptions else { return }
//                self.nioHandler = UDPNIOHandler(options: options, groupProvider: provider, group: self.group!)
//            }
//#else
//            
//#endif
//        }
//    
//    private func handleAccountChange() {
//        connectIfNecessary()
//    }
//    
//    private func connectIfNecessary() {
//        guard case .offline = state else { return }
//        state = .connecting(self.nioHandler!)
//        let promise = self.group!.next().makePromise(of: Channel.self)
//        let connected = self.nioHandler?.connect(promise: promise)
//        connected?.whenFailure { error in
//            promise.fail(error)
//        }
//    }
//    
//    private func clientOptionsForParticipant(_ ckAccount: CKAccount) -> VideoClientOptions? {
//        guard let nick = IRCNickName(ckAccount.nickname) else { return nil }
//        return VideoClientOptions(
//            port: ckAccount.port,
//            host: ckAccount.host,
//            tls: ckAccount.tls,
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
//    public func sessionWithId(_ id: String) -> VideoSession? {
//        return sessions[id.lowercased()]
//    }
//    
//    @discardableResult
//    public func registerSession(_ name: String) -> VideoSession? {
//        let id = name.lowercased()
//        if let s = sessions[id] { return s }
//        guard let s = VideoSession(serviceDelegate: self, groupSessionName: name) else { return nil }
//        sessions[id] = s
//        return s
//    }
//    
//    public func unregisterSession(_ name: String) {
//        sessions.removeValue(forKey: name.lowercased())?.userDidLeaveChannel()
//    }
//    
//    @discardableResult
//    public func registerPrivateSession(_ name: String) -> VideoSession? {
//        let id = name.lowercased()
//        if let s = sessions[id] { return s }
//        guard let s = VideoSession(serviceDelegate: self, nickname: name) else { return nil }
//        sessions[id] = s
//        return s
//    }
//    
//    public func sessionsForParticipant(_
//                                       participant: IRCMessageRecipient,
//                                       create: Bool = false
//    ) -> [ VideoSession ] {
//        switch participant {
//        case .channel (let name):
//            let id = name.stringValue.lowercased()
//            if let c = sessions[id] { return [ c ] }
//            guard create else { return [] }
//            let new = VideoSession(serviceDelegate: self, groupSessionName: name)
//            sessions[id] = new
//            return [ new ]
//            
//        case .nickname(let name):
//            let id = name.stringValue.lowercased()
//            if let c = sessions[id] { return [ c ] }
//            guard create else { return [] }
//            guard let new = VideoSession(serviceDelegate: self, nickname: name.stringValue) else { return [] }
//            sessions[id] = new
//            return [ new ]
//            
//        case .everything:
//            return Array(sessions.values)
//        }
//    }
//    
//    public func sessionsForParticipants(_
//                                        participants: [ IRCMessageRecipient ],
//                                        create: Bool = false
//    ) -> [ VideoSession ] {
//        var results = [ ObjectIdentifier: VideoSession]()
//        for participant in participants {
//            for session in sessionsForParticipant(participant) {
//                results[ObjectIdentifier(session)] = session
//            }
//        }
//        return Array(results.values)
//    }
//}
//
//extension VideoKit: CustomStringConvertible {
//    public var description: String { "<Service: \(ckAccount)>" }
//}
//
//
