import NIO
import Logging
import NeedleTailHelpers
import CypherMessaging
#if canImport(Network)
import NIOTransportServices
#endif

public final class IRCClient: AsyncIRCDelegate {
    
    //AsyncIRCProtocol
    var cypher: CypherMessenger?
    public var userConfig: UserConfig?
    public var acknowledgment: Acknowledgment.AckType = .none
    public var origin: String? { return clientContext.nickname.name }
    public var tags: [IRCTags]?
    public let clientInfo: ClientContext.ServerClientInfo
    public let clientContext: ClientContext
    public let eventLoop: EventLoop
    public var channel: Channel?
//    var usermask : String? {
//        guard case .registered(_, let nick, let info) = transportState.current else { return nil }
//        let host = info.servername ?? clientInfo.hostname
//        return "\(nick.stringValue)!~\(info.username)@\(host)"
//    }
    let groupManager: EventLoopGroupManager
    var messageOfTheDay = ""
    var subscribedChannels = Set<IRCChannelName>()
    var logger: Logger
    var proceedNewDeivce = false
    var alertType: AlertType = .registryRequestRejected
//    var nick: NeedleTailNick? { return clientContext.nickname }
    var userInfo: IRCUserInfo?
    var transportState: TransportState
    var userMode = IRCUserMode()
    #if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
    var notifications = AsyncIRCNotifications()
    #endif
    public var registrationPacket = ""
    weak var delegate: IRCDispatcher?
    weak var transportDelegate: CypherTransportClientDelegate?
    
    public init(
        cypher: CypherMessenger?,
        clientContext: ClientContext,
        transportState: TransportState,
        transportDelegate: CypherTransportClientDelegate?
    ) {
        self.cypher = cypher
        self.transportState = transportState
        self.clientContext = clientContext
        self.clientInfo = clientContext.clientInfo
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
