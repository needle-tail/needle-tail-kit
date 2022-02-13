//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2020 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOExtras
import Logging
#if canImport(Network)
import NIOTransportServices
#endif

/**
 * A simple IRC client based on SwiftNIO.
 *
 * Checkout swift-nio-irc-eliza or swift-nio-irc-webclient for examples on this.
 *
 * The basic flow is:
 * - create a `IRCClient` object, quite likely w/ custom `IRCClientOptions`
 * - implement and assign an `IRCClientDelegate`, which is going to handle
 *   incoming commands
 * - `connect` the client
 */
open class IRCClient : IRCClientMessageTarget {
    
    public let options   : IRCClientOptions
    public let eventLoop : EventLoop
    public var delegate  : IRCClientDelegate?
    public var tags: [IRCTags]?
    let groupManager: EventLoopGroupManager
    
    public enum Error : Swift.Error {
        case writeError(Swift.Error)
        case stopped
        case notImplemented
        case internalInconsistency
        case unexpectedInput
        case channelError(Swift.Error)
    }
    
    enum State : CustomStringConvertible {
        case disconnected
        case connecting
        case registering(channel: Channel, nick: IRCNickName, userInfo: IRCUserInfo)
        case registered (channel: Channel, nick: IRCNickName, userInfo: IRCUserInfo)
        case error      (Error)
        case requestedQuit
        case quit
        
        var isRegistered : Bool {
            switch self {
            case .registered: return true
            default:          return false
            }
        }
        
        var nick : IRCNickName? {
            get {
                switch self {
                case .registering(_, let v, _): return v
                case .registered (_, let v, _): return v
                default: return nil
                }
            }
        }
        
        var userInfo : IRCUserInfo? {
             get {
                switch self {
                case .registering(_, _, let v): return v
                case .registered (_, _, let v): return v
                default: return nil
                }
            }
        }
        
        var channel : Channel? {
            get {
                switch self {
                case .registering(let channel, _, _): return channel
                case .registered (let channel, _, _): return channel
                default: return nil
                }
            }
        }
        
        var canStartConnection : Bool {
            switch self {
            case .disconnected, .error: return true
            case .connecting:           return false
            case .registering:          return false
            case .registered:           return false
            case .requestedQuit, .quit: return false
            }
        }
        
        var description : String {
            switch self {
            case .disconnected:                return "disconnected"
            case .connecting:                  return "connecting..."
            case .registering(_, let nick, _): return "registering<\(nick)>..."
            case .registered (_, let nick, _): return "registered<\(nick)>"
            case .error      (let error):      return "error<\(error)>"
            case .requestedQuit:               return "quitting..."
            case .quit:                        return "quit"
            }
        }
    }
    
    private var state : State = .disconnected
    private var userMode = IRCUserMode()
    
    var usermask : String? {
        guard case .registered(_, let nick, let info) = state else { return nil }
        let host = info.servername ?? options.hostname ?? "??"
        return "\(nick.stringValue)!~\(info.username)@\(host)"
    }
    
    var logger: Logger
    internal var store: NeedleTailStore
    
    public init(options: IRCClientOptions, store: NeedleTailStore) {
        self.options = options
        self.store = store
        let eventLoop = options.eventLoopGroup?.next()
        self.eventLoop = eventLoop!
        self.logger = Logger(label: "NeedleTail Client Logger")
        if options.eventLoopGroup == nil {
#if canImport(Network)
            if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
                options.eventLoopGroup = NIOTSEventLoopGroup()
            } else {
                print("Sorry, your OS is too old for Network.framework.")
                exit(0)
            }
#else
            options.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        }
        let provider: EventLoopGroupManager.Provider = options.eventLoopGroup.map { .shared($0) } ?? .createNew
        self.groupManager = EventLoopGroupManager(provider: provider)
    }
    
    deinit {
        _ = channel?.close(mode: .all)
    }
    
    
    // MARK: - Commands
    
    open func changeNick(_ nick: IRCNickName) async {
        await send(.NICK(nick))
    }
    
    
    // MARK: - Connect
    
    var retryInfo = IRCRetryInfo()
    var channel : Channel? { get { return state.channel } }
    
    
    internal func _connect(host: String, port: Int) async throws -> Channel {
        clearListCollectors()
        userMode = IRCUserMode()
        state    = .connecting
        retryInfo.attempt += 1
        
        return try await clientBootstrap()
            .connect(host: host, port: port).get()
    }
    
    //Shutdown the program
    public func disconnect() async {
        await close()
    }
    
    private func clientBootstrap() async throws -> NIOClientTCPBootstrap {
        let bootstrap: NIOClientTCPBootstrap
        guard let host = options.hostname else {
            throw Error.notImplemented
        }

        if !options.tls {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: false)
        } else {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: true)
        }
        let store = self.store
        return bootstrap
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline
                    .addHandlers([
//                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        IRCChannelHandler(logger: self.logger, store: store),
                        Handler(client: self)
                    ])
            }
    }
    
    
    public func connecting() async throws -> Channel? {
        var channel: Channel?
        do {
            channel = try await _connect(host: options.hostname ?? "localhost", port: options.port)
            await self.retryInfo.registerSuccessfulConnect()
            guard case .connecting = self.state else {
                assertionFailure("called \(#function) but we are not connecting?")
                return channel
            }
            self.state = .registering(channel: channel!,
                                      nick:     self.options.nickname,
                                      userInfo: self.options.userInfo)
            await self._register()
        } catch {
            await self.close()
        }
        assert(channel != nil, "channel is nil")
        return channel
    }
    
    
    private func _register() async {
        guard case .registering(_, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        if let pwd = options.password {
            await send(.otherCommand("PASS", [ pwd ]))
        }

        await send(.NICK(nick))
        await send(.USER(user))
    }
    
    func _closeOnUnexpectedError(_ error: Swift.Error? = nil) {
        assert(eventLoop.inEventLoop, "threading issue")
        
        if let error = error {
            self.retryInfo.lastSocketError = error
        }
    }
    
    internal func close() async {
        do {
            _ = try await channel?.close(mode: .all)
            try await self.groupManager.syncShutdown()
            clearListCollectors()
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        print("closed server")
    }
    
    
    // MARK: - Subscriptions
    
    var subscribedChannels = Set<IRCChannelName>()
    
    private func _resubscribe() {
        if !subscribedChannels.isEmpty {
            // TODO: issues JOIN commands
        }
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
    
    func handleRegistrationDone() async {
        guard case .registering(let channel, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        
        state = .registered(channel: channel, nick: nick, userInfo: user)
        await delegate?.client(self, registered: nick, with: user)
        
        self._resubscribe()
    }
    
    func handleRegistrationFailed(with message: IRCMessage) async {
        guard case .registering(_, let nick, _) = state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        // TODO: send to delegate
        print("ERROR: registration of \(nick) failed:", message)
        
        await delegate?.clientFailedToRegister(self)
        _closeOnUnexpectedError()
    }
    
    
    // MARK: - List Collectors
    
    var messageOfTheDay = ""
    
    func clearListCollectors() {
        messageOfTheDay = ""
    }
    
    
    // MARK: - Handler Delegate
    
    func handlerDidDisconnect(_ context: ChannelHandlerContext) async {
        switch state {
        case .error:
            break
        case .quit:
            break
        case .registering, .connecting:
            await  delegate?.clientFailedToRegister(self)
            state = .disconnected
        default:
            state = .disconnected
        }
    }
    
    func handlerHandleResult(_ message: IRCMessage) async {
        if case .registering = state {
            if message.command.signalsSuccessfulRegistration {
                await handleRegistrationDone()
            }
            
            if case .numeric(.errorNicknameInUse, _) = message.command {
                print("NEEDS NEW NICK!")
                // TODO: recover using a callback
                return await handleRegistrationFailed(with: message)
            }
            else if message.command.isErrorReply {
                return await handleRegistrationFailed(with: message)
            }
        }
        
        do {
            try await irc_msgSend(message)
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
    
    
    // MARK: - Handler
    
    final class Handler : ChannelInboundHandler {
        
        typealias InboundIn = IRCMessage
        
        let client : IRCClient
        
        init(client: IRCClient) {
            self.client = client
        }
        
        func channelActive(context: ChannelHandlerContext) {
            print("Active")
        }
        
        func channelInactive(context: ChannelHandlerContext) {
            Task {
                await client.handlerDidDisconnect(context)
            }
        }
        
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            Task {
                let value = unwrapInboundIn(data)
                await client.handlerHandleResult(value)
            }
        }
        
        func errorCaught(context: ChannelHandlerContext, error: Error) {
            self.client.handlerCaughtError(error, in: context)
            context.close(promise: nil)
        }
    }
    
    
    // MARK: - Writing
        public var origin : String? { return nil }
    public func sendMessages<T: Collection>(_ messages: T) async
    where T.Element == IRCMessage
    {
        // TBD: this looks a little more difficult than necessary.
        guard let channel = channel else {
            print("fail")
            return
        }

        let count = messages.count
        if count == 0 {
            print("succeed")
            return
        }
        if count == 1 {
            do {
                guard let message = messages.first else { return }
                print("sendMEssage Message_____ \(message)")
                try await channel.writeAndFlush(message)
            } catch {
                print(error)
            }
        }
//        channel.flush()
  }
}

extension ChannelOptions {
    static let reuseAddr = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
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


extension IRCClient : IRCDispatcher {
    
    public func irc_msgSend(_ message: IRCMessage) async throws {
        do {
            return try await irc_defaultMsgSend(message)
        }
        catch let error as IRCDispatcherError {
            guard case .doesNotRespondTo = error else { throw error }
        }
        catch { throw error }
        
        switch message.command {
            /* Message of the Day coalescing */
        case .numeric(.replyMotDStart, let args):
            messageOfTheDay = (args.last ?? "") + "\n"
        case .numeric(.replyMotD, let args):
            messageOfTheDay += (args.last ?? "") + "\n"
        case .numeric(.replyEndOfMotD, _):
            if !messageOfTheDay.isEmpty {
                await delegate?.client(self, messageOfTheDay: messageOfTheDay)
            }
            messageOfTheDay = ""
            
            /* name reply */
            // <IRCCmd: 353 args=Guest1,=,#ZeeQL,Guest1> localhost -
            // <IRCCmd: 366 args=Guest1,#ZeeQL,End of /NAMES list> localhost -
        case .numeric(.replyNameReply, _ /*let args*/):
#if false
            // messageOfTheDay += (args.last ?? "") + "\n"
#else
            break
#endif
        case .numeric(.replyEndOfNames, _):
#if false
            if !messageOfTheDay.isEmpty {
                delegate?.client(self, messageOfTheDay: messageOfTheDay)
            }
            messageOfTheDay = ""
#else
            break
#endif
            
        case .numeric(.replyTopic, let args):
            // :localhost 332 Guest31 #NIO :Welcome to #nio!
            guard args.count > 2, let channel = IRCChannelName(args[1]) else {
                return print("ERROR: topic args incomplete:", message)
            }
            await delegate?.client(self, changeTopic: args[2], of: channel)
            
            /* join/part, we need the origin here ... (fix dispatcher) */
            
        case .JOIN(let channels, _):
            guard let origin = message.origin, let user = IRCUserID(origin) else {
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            await delegate?.client(self, user: user, joined: channels)
            
        case .PART(let channels, let leaveMessage):
            guard let origin = message.origin, let user = IRCUserID(origin) else {
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            await delegate?.client(self, user: user, left: channels, with: leaveMessage)
            
            /* unexpected stuff */
            
        case .otherNumeric(let code, let args):
#if false
            print("OTHER NUM:", code, args)
#endif
            await delegate?.client(self, received: message)
        case .QUIT(let message):
            await delegate?.client(self, quit: message)
        default:
#if false
            print("OTHER COMMAND:", message.command,
                  message.origin ?? "-", message.target ?? "-")
#endif
            await delegate?.client(self, received: message)
        }
    }
    
    open func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws {
        await delegate?.client(self, notice: message, for: recipients)
    }
    
    open func doMessage(sender     : IRCUserID?,
                        recipients : [ IRCMessageRecipient ],
                        message    : String,
                        tags       : [IRCTags]?) async throws {
        guard let sender = sender else { // should never happen
            assertionFailure("got empty message sender!")
            return
        }
        await delegate?.client(self, message: message, from: sender, for: recipients)
    }
    
    open func doNick(_ newNick: IRCNickName) async throws {
        switch state {
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            state = .registering(channel: channel, nick: newNick, userInfo: info)
            
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            state = .registered(channel: channel, nick: newNick, userInfo: info)
            
        default: return // hmm
        }
        
        await delegate?.client(self, changedNickTo: newNick)
    }
    
    open func doMode(nick: IRCNickName, add: IRCUserMode, remove: IRCUserMode) async throws {
        guard let myNick = state.nick, myNick == nick else {
            return
        }
        
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            await delegate?.client(self, changedUserModeTo: newMode)
        }
    }
    
    open func doPing(_ server: String, server2: String? = nil) async throws {
        let msg: IRCMessage
        
        msg = IRCMessage(origin: origin, // probably wrong
                         command: .PONG(server: server, server2: server))
         sendMessage(msg)
    }
}
