import NIO
import Logging
import NeedleTailHelpers
import CypherMessaging
#if canImport(Network)
import NIOTransportServices
#endif

public final class IRCClient: IRCMessengerProtocol {
    
    //IRCMessengerProtocol
    public var userConfig: UserConfig?
    public var acknowledgment: Acknowledgment.AckType = .none
    public var origin: String? { return nick?.stringValue }
    public var tags: [IRCTags]?
    public let options: IRCClientOptions
    public let eventLoop: EventLoop
    public var channel: Channel?
    var usermask : String? {
        guard case .registered(_, let nick, let info) = userState.state else { return nil }
        let host = info.servername ?? options.hostname ?? "??"
        return "\(nick.stringValue)!~\(info.username)@\(host)"
    }
    let groupManager: EventLoopGroupManager
    var messageOfTheDay = ""
    var subscribedChannels = Set<IRCChannelName>()
    var logger: Logger
    var retryInfo = IRCRetryInfo()
    var nick: NeedleTailNick?
    var userInfo: IRCUserInfo?
    var userState: UserState
    var userMode = IRCUserMode()
    weak var delegate: IRCDispatcher?
    weak var transportDelegate: CypherTransportClientDelegate?
    
    public init(
        options: IRCClientOptions,
        userState: UserState,
        transportDelegate: CypherTransportClientDelegate?
    ) {
        self.userState = userState
        self.options = options
        let group: EventLoopGroup?
        self.logger = Logger(label: "NeedleTail Client Logger")
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

        self.eventLoop = group!.next()
        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        self.groupManager = EventLoopGroupManager(provider: provider)
        self.delegate = self
        self.transportDelegate = transportDelegate
    }
    
    deinit {
        _ = channel?.close(mode: .all)
    }
}

extension IRCClient: Equatable {
    public static func == (lhs: IRCClient, rhs: IRCClient) -> Bool {
        return lhs === rhs
    }
}
