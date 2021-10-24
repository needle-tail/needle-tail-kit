//  IRCNIOHandler.swift
//  Cartisim
//
//  Created by Cole M on 3/9/21.
//  Copyright © 2021 Cole M. All rights reserved.
//
import Foundation
import Network
import NIO
import NIOSSL
import NIOExtras
import NIOTransportServices
import ArgumentParser
import NIOIRC


public class IRCNIOHandler: IRCClientMessageTarget {
    
    let groupManager: EventLoopGroupManager
    public let options   : IRCClientOptions
    public let eventLoop : EventLoop
    public var delegate  : IRCClientDelegate?
    var retryInfo = IRCRetryInfo()
    var channel : Channel? { @inline(__always) get { return state.channel } }
    internal var state : IRCState = .disconnected
    internal var userMode = IRCUserMode()
    var messageOfTheDay = ""
    public var origin : String? { return nil }
    var usermask : String? {
        guard case .registered(_, let nick, let info) = state else { return nil }
        let host = info.servername ?? options.hostname ?? "??"
        return "\(nick.stringValue)!~\(info.username)@\(host)"
    }
    
    
    ///Here in our initializer we need to inject our host, port, and whether or not we will be sending an encrypted obejct from the client.
    ///Client initialitaion will look like this `CartisimIRCClient(host: "localhost", port, 8081, isEncryptedObject: true, tls: Bool)`
    internal init(
        options: IRCClientOptions,
        groupProvider provider: EventLoopGroupManager.Provider,
        group: EventLoopGroup?
    ) {
        self.options = options
        self.groupManager = EventLoopGroupManager(provider: provider)
        let eventLoop = group?.next()
        self.eventLoop = eventLoop!
    }
    
    deinit {
        _ = channel?.close(mode: .all)
    }
    
    
    internal func connect() {
        guard eventLoop.inEventLoop else { return eventLoop.execute(self.connect) }
        
        guard state.canStartConnection else { return }
        _ = try? _connect(host: options.hostname ?? "localhost", port: options.port)
    }
    
    internal func _connect(host: String, port: Int) throws -> EventLoopFuture<Channel> {
//    internal func _connect(host: String, port: Int) throws {
        assert(eventLoop.inEventLoop,    "threading issue")
        assert(state.canStartConnection, "cannot start connection!")
        
        clearListCollectors()
        userMode = IRCUserMode()
        state    = .connecting
        retryInfo.attempt += 1
        
        return try clientBootstrap()
            .connect(host: host, port: port)
            .map { channel -> Channel in
                print(channel, "MY CHANNEL__________1")
                              self.retryInfo.registerSuccessfulConnect()
              
                              guard case .connecting = self.state else {
                                  assertionFailure("called \(#function) but we are not connecting?")
                                  return channel
                              }
                              print(channel, "MY CHANNEL__________2")
                              self.state = .registering(channel: channel,
                                                        nick:     self.options.nickname,
                                                        userInfo: self.options.userInfo)
                              self._register()
                              print(channel, "MY CHANNEL__________3")
                
                              return channel
            }
    }
    
    //Shutdown the program
    public func disconnect() {
        do {
            try groupManager.syncShutdown()
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        print("closed server")
    }
    
    private func clientBootstrap() throws -> NIOClientTCPBootstrap {
        let bootstrap: NIOClientTCPBootstrap
        guard let host = options.hostname else { throw IRCClientError.nilHostname }
        if !options.tls {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: false)
        } else {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: true)
        }
        
        return bootstrap
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
//                guard let strongSelf = self else {
//                    let error = channel.eventLoop.makePromise(of: Void.self)
//                    error.fail(IRCClientError.internalInconsistency)
//                    return error.futureResult
//                }
                
                
                // WE have an issue flat mapping the channel pipeline
                return channel.pipeline
                                    .addHandler(IRCChannelHandler(), name: "io.cartisim.nio.irc.protocol")
                                    .flatMap { [weak self] _ in
//                                      guard let strongSelf = self else {
//                                        let error = channel.eventLoop.makePromise(of: Void.self)
//                                        error.fail(IRCClientError.internalInconsistency)
//                                        return error.futureResult
//                                      }
                                        print(channel.pipeline, "pipeline")
                                      let c = channel.pipeline
                                            .addHandler(IRCHandler(client: self!),
                                                    name: "io.cartisim.nio.irc.client")
                                        print(c, "Handler pipe")
                                        return c
                                    }
                
                
//                    .addHandlers([
//                        IRCChannelHandler(),
//                        Handler(client: strongSelf)
//                    ])
//                print(c, "PIPES")
//                return c
            }
        
    }
    
    // MARK: - Commands
    open func changeNick(_ nick: IRCNickName) {
        send(.NICK(nick))
    }
    
    
    // MARK: - Connect
    private func _register() {
        assert(eventLoop.inEventLoop, "threading issue")
        
        guard case .registering(_, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        if let pwd = options.password {
            send(.otherCommand("PASS", [ pwd ]))
        }
        
        send(.NICK(nick))
        send(.USER(user))
    }
    
    func _closeOnUnexpectedError(_ error: Swift.Error? = nil) {
        assert(eventLoop.inEventLoop, "threading issue")
        
        if let error = error {
            self.retryInfo.lastSocketError = error
        }
    }
    
    open func close() {
        guard eventLoop.inEventLoop else { return eventLoop.execute(close) }
        _ = channel?.close(mode: .all)
        clearListCollectors()
    }
    
    
    // MARK: - Subscriptions
    var subscribedChannels = Set<IRCChannelName>()
    
    private func _resubscribe() {
        if !subscribedChannels.isEmpty {
            // TODO: issues JOIN commands
        }
        
        // TODO: we have no queue, right?
        // _processQueue()
    }
    
    
    // MARK: - Retry
    
#if false // TODO: finish Noze port
    private func retryConnectAfterFailure() {
        let retryHow : IRCRetryResult
        
        if let cb = options.retryStrategy {
            retryHow = cb(retryInfo)
        }
        else {
            if retryInfo.attempt < 10 {
                retryHow = .retryAfter(TimeInterval(retryInfo.attempt) * 0.200)
            }
            else {
                retryHow = .stop
            }
        }
        
        switch retryHow {
        case .retryAfter(let timeout):
            // TBD: special Retry status?
            if state != .connecting {
                state = .connecting
                eventLoop.scheduleTask(in: .milliseconds(timeout * 1000.0)) {
                    self.state = .disconnected
                    self.connect()
                }
            }
            
        case .error(let error):
            stop(error: error)
            
        case .stop:
            stop(error: IRCClientError.ConnectionQuit)
        }
    }
#endif
    
    func handleRegistrationDone() {
        guard case .registering(let channel, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        
        state = .registered(channel: channel, nick: nick, userInfo: user)
        delegate?.client(self, registered: nick, with: user)
        
        self._resubscribe()
    }
    
    func handleRegistrationFailed(with message: IRCMessage) {
        guard case .registering(_, let nick, _) = state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        // TODO: send to delegate
        print("ERROR: registration of \(nick) failed:", message)
        
        delegate?.clientFailedToRegister(self)
        _closeOnUnexpectedError()
    }
    
    
    // MARK: - List Collectors
    func clearListCollectors() {
        messageOfTheDay = ""
    }
    
    
    // MARK: - Handler Delegate
    func handlerDidDisconnect(_ context: ChannelHandlerContext) { // Q: own
        switch state {
        case .error, .quit: break // already handled
        case .registering, .connecting:
            delegate?.clientFailedToRegister(self)
            state = .disconnected
        default:
            state = .disconnected
        }
    }
    
    func handlerHandleResult(_ message: IRCMessage) { // Q: own
        if case .registering = state {
            if message.command.signalsSuccessfulRegistration {
                handleRegistrationDone()
            }
            
            if case .numeric(.errorNicknameInUse, _) = message.command {
                print("NEEDS NEW NICK!")
                // TODO: recover using a callback
                return handleRegistrationFailed(with: message)
            }
            else if message.command.isErrorReply {
                return handleRegistrationFailed(with: message)
            }
        }
        
        do {
            try irc_msgSend(message)
        }
        catch let error as IRCDispatcherError {
            // TBD:
            print("handle dispatcher error:", error)
        }
        catch {
            // TBD:
            print("handle generic error:", type(of: error), error)
        }
        
    }
    
    func handlerCaughtError(_ error: Swift.Error,
                            in context: ChannelHandlerContext) {
        retryInfo.lastSocketError = error
        state = .error(.channelError(error))
        
        print("IRCClient error:", error)
    }
    
    
    
    // MARK: - Writing
    public func sendMessages<T: Collection>(_ messages: T,
                                            promise: EventLoopPromise<Void>?)
    where T.Element == IRCMessage {
        // TBD: this looks a little more difficult than necessary.
        guard let channel = channel else {
            promise?.fail(IRCClientError.stopped)
            return
        }
        
        guard channel.eventLoop.inEventLoop else {
            return channel.eventLoop.execute {
                self.sendMessages(messages, promise: promise)
            }
        }
        
        let count = messages.count
        if count == 0 {
            promise?.succeed(())
            return
        }
        if count == 1 {
            return channel.writeAndFlush(messages.first!, promise: promise)
        }
        
        guard let promise = promise else {
            for message in messages {
                channel.write(message, promise: nil)
            }
            return channel.flush()
        }
        
        EventLoopFuture<Void>
            .andAllSucceed(messages.map { channel.write($0) },
                           on: promise.futureResult.eventLoop)
            .cascade(to: promise)
        channel.flush()
    }
}

extension ChannelOptions {
    
    static let reuseAddr =
    ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                          SO_REUSEADDR)
    
}

extension IRCCommand {
    
    var isErrorReply : Bool {
        guard case .numeric(let code, _) = self else { return false }
        return code.rawValue >= 400 // Hmmm
    }
    
    var signalsSuccessfulRegistration : Bool {
        switch self {
        case .MODE: return true // Freenode sends a MODE
        case .numeric(let code, _):
            switch code {
            case .replyWelcome, .replyYourHost, .replyMotD, .replyEndOfMotD:
                return true
            default:
                return false
            }
            
        default: return false
        }
    }
    
}

