//
//  File.swift
//  
//
//  Created by Cole M on 10/30/21.
//

import Foundation



import NIO
import NIOIRC

#if canImport(NIOTransportServices)
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
    
  private var activeClientOptions : IRCClientOptions?
  private var state : IRCState = .disconnected
  private var userMode = IRCUserMode()
//  private var niotsHandler: IRCNIOHandler?
    let groupManager: EventLoopGroupManager
    
  var usermask : String? {
    guard case .registered(_, let nick, let info) = state else { return nil }
    let host = info.servername ?? options.hostname ?? "??"
    return "\(nick.stringValue)!~\(info.username)@\(host)"
  }

  
  public init(options: IRCClientOptions) {
    self.options = options
    let eventLoop = options.eventLoopGroup?.next()
    self.eventLoop = eventLoop!
      
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
  
  open func changeNick(_ nick: IRCNickName) {
    send(.NICK(nick))
  }

  
  // MARK: - Connect
  
  var retryInfo = IRCRetryInfo()
  var channel : Channel? { @inline(__always) get { return state.channel } }

    
    
    internal func connect(promise: EventLoopPromise<Channel>) -> EventLoopFuture<Channel> {
        let future = try? _connect(host: options.hostname ?? "localhost", port: options.port)
        future?.whenComplete { switch $0 {
        case .success(let channel):
            promise.succeed(channel)
        case .failure(let error):
            try? self.groupManager.syncShutdown()
            promise.fail(error)
        }
        }
        return promise.futureResult
    }
    
    internal func _connect(host: String, port: Int) throws -> EventLoopFuture<Channel> {
//        assert(eventLoop.inEventLoop,    "threading issue")
//        assert(state.canStartConnection, "cannot start connection!")
        
        clearListCollectors()
        userMode = IRCUserMode()
        state    = .connecting
        retryInfo.attempt += 1
        
        return try clientBootstrap()
            .connect(host: host, port: port)
            .map { channel -> Channel in
                self.retryInfo.registerSuccessfulConnect()
                
                guard case .connecting = self.state else {
                    assertionFailure("called \(#function) but we are not connecting?")
                    return channel
                }
                self.state = .registering(channel: channel,
                                          nick:     self.options.nickname,
                                          userInfo: self.options.userInfo)
                self._register()

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
                return channel.pipeline
                    .addHandler(IRCChannelHandler(), name: "io.cartisim.nio.irc.protocol")
                    .flatMap { [weak self] _ in
                      guard let strongSelf = self else {
                        let error = channel.eventLoop.makePromise(of: Void.self)
                        error.fail(IRCClientError.internalInconsistency)
                        return error.futureResult
                      }
                      return channel.pipeline
                            .addHandler(IRCHandler(client: strongSelf),
                                    name: "io.cartisim.nio.irc.client")
                    }
            }
        
    }
    
    
    
    
    public func connecting() {
        guard let group = self.options.eventLoopGroup else { return }
        let promise = group.next().makePromise(of: Channel.self)
        let connected = self.connect(promise: promise)
        connected.whenComplete { switch $0 {
        case .success(let success):
            print(success)
            promise.succeed(success)
        case .failure(let error):
            promise.fail(error)
            self.eventLoop.execute {
                self.connecting()
            }
        }
        }
    }
  
    public func disconnecting() {
        self.disconnect()
    }
    
    
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
  
  var messageOfTheDay = ""
  
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
                          in context: ChannelHandlerContext) // Q: own
  {
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
    }
    func channelInactive(context: ChannelHandlerContext) {
      client.handlerDidDisconnect(context)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let value = unwrapInboundIn(data)
      client.handlerHandleResult(value)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
      self.client.handlerCaughtError(error, in: context)
      context.close(promise: nil)
    }
  }

  
  // MARK: - Writing
  
  public var origin : String? { return nil }
  
  public func sendMessages<T: Collection>(_ messages: T,
                                          promise: EventLoopPromise<Void>?)
                where T.Element == IRCMessage
  {
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

extension IRCClient : IRCDispatcher {
  
  public func irc_msgSend(_ message: NIOIRC.IRCMessage) throws {
    do {
      return try irc_defaultMsgSend(message)
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
          delegate?.client(self, messageOfTheDay: messageOfTheDay)
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
        delegate?.client(self, changeTopic: args[2], of: channel)

      /* join/part, we need the origin here ... (fix dispatcher) */
        
      case .JOIN(let channels, _):
        guard let origin = message.origin, let user = IRCUserID(origin) else {
          return print("ERROR: JOIN is missing a proper origin:", message)
        }
        delegate?.client(self, user: user, joined: channels)
      
      case .PART(let channels, let leaveMessage):
        guard let origin = message.origin, let user = IRCUserID(origin) else {
          return print("ERROR: JOIN is missing a proper origin:", message)
        }
        delegate?.client(self, user: user, left: channels, with: leaveMessage)

      /* unexpected stuff */

      case .otherNumeric(let code, let args):
        #if false
          print("OTHER NUM:", code, args)
        #endif
        delegate?.client(self, received: message)

      default:
        #if false
          print("OTHER COMMAND:", message.command,
                message.origin ?? "-", message.target ?? "-")
        #endif
        delegate?.client(self, received: message)
    }
  }
  
  open func doNotice(recipients: [ IRCMessageRecipient ], message: String)
              throws
  {
    delegate?.client(self, notice: message, for: recipients)
  }
  
  open func doMessage(sender     : IRCUserID?,
                      recipients : [ IRCMessageRecipient ],
                      message    : String) throws
  {
    guard let sender = sender else { // should never happen
      assertionFailure("got empty message sender!")
      return
    }
    delegate?.client(self, message: message, from: sender, for: recipients)
  }

  open func doNick(_ newNick: IRCNickName) throws {
    switch state {
      case .registering(let channel, let nick, let info):
        guard nick != newNick else { return }
        state = .registering(channel: channel, nick: newNick, userInfo: info)
      
      case .registered(let channel, let nick, let info):
        guard nick != newNick else { return }
        state = .registered(channel: channel, nick: newNick, userInfo: info)

      default: return // hmm
    }
    
    delegate?.client(self, changedNickTo: newNick)
  }
  
  open func doMode(nick: IRCNickName, add: IRCUserMode, remove: IRCUserMode)
              throws
  {
    guard let myNick = state.nick, myNick == nick else {
      return
    }
    
    var newMode = userMode
    newMode.subtract(remove)
    newMode.formUnion(add)
    if newMode != userMode {
      userMode = newMode
      delegate?.client(self, changedUserModeTo: newMode)
    }
  }

  open func doPing(_ server: String, server2: String? = nil) throws {
    let msg : IRCMessage
    
    msg = IRCMessage(origin: origin, // probably wrong
                     command: .PONG(server: server, server2: server))
    sendMessage(msg)
  }
}
