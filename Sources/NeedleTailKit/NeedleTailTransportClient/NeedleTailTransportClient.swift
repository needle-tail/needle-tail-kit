import NIO
import Logging
import NeedleTailHelpers
import CypherMessaging
import AsyncIRC
#if canImport(Network)
import NIOTransportServices
#endif

@NeedleTailTransportActor
final class NeedleTailTransportClient: AsyncIRCDelegate {
    
    //AsyncIRCProtocol
    //    var usermask : String? {
    //        guard case .registered(_, let nick, let info) = transportState.current else { return nil }
    //        let host = info.servername ?? clientInfo.hostname
    //        return "\(nick.stringValue)!~\(info.username)@\(host)"
    //    }
    //    var nick: NeedleTailNick? { return clientContext.nickname }
    var cypher: CypherMessenger
    var messenger: NeedleTailMessenger
    public var userConfig: UserConfig?
    public var acknowledgment: Acknowledgment.AckType = .none
    public var origin: String? {
        return try? BSONEncoder().encode(clientContext.nickname).makeData().base64EncodedString()
    }
    public var tags: [IRCTags]?
    public let clientContext: ClientContext
    public let clientInfo: ClientContext.ServerClientInfo
    public let eventLoop: EventLoop?
    public var channel: Channel?
    let groupManager: EventLoopGroupManager
    var messageOfTheDay = ""
    var subscribedChannels = Set<IRCChannelName>()
    var logger: Logger
    var proceedNewDeivce = false
    var alertType: AlertType = .registryRequestRejected
    var userInfo: IRCUserInfo?
    var transportState: TransportState
    var userMode = IRCUserMode()
    var registrationPacket = ""
    let signer: TransportCreationRequest
    var authenticated: AuthenticationState
    var channelBlob: String?
    weak var delegate: IRCDispatcher?
    weak var transportDelegate: CypherTransportClientDelegate?
    
    init(
        cypher: CypherMessenger,
        messenger: NeedleTailMessenger,
        transportState: TransportState,
        transportDelegate: CypherTransportClientDelegate?,
        signer: TransportCreationRequest,
        authenticated: AuthenticationState,
        clientContext: ClientContext
    ) async {
        self.cypher = cypher
        self.messenger = messenger
        self.transportState = transportState
        self.clientContext = clientContext
        self.clientInfo = clientContext.clientInfo
        self.signer = signer
        self.authenticated = authenticated
        self.transportState = transportState
        self.logger = Logger(label: "NeedleTail Client Logger")
        self.transportDelegate = transportDelegate
        
        let group: EventLoopGroup?
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
    }
    
    deinit {
        let task = Task {
            _ = try? await channel?.close(mode: .all).get()
        }
        task.cancel()
    }
}

extension NeedleTailTransportClient: Equatable {
    static func == (lhs: NeedleTailTransportClient, rhs: NeedleTailTransportClient) -> Bool {
        return lhs === rhs
    }
}
