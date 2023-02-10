import NIO
import Logging
import NeedleTailHelpers
import CypherMessaging
import NeedleTailProtocol
#if canImport(Network)
import NIOTransportServices
#endif

//@NeedleTailClientActor
final class NeedleTailClient {
    
    public var clientContext: ClientContext
    public let clientInfo: ClientContext.ServerClientInfo
    var eventLoop: EventLoop?
    var cypher: CypherMessenger?
    var messenger: NeedleTailMessenger
    let groupManager: EventLoopGroupManager
    let signer: TransportCreationRequest?
    var transportState: TransportState
    var userInfo: IRCUserInfo?
    var userMode = IRCUserMode()
    @NeedleTailTransportActor
    var transport: NeedleTailTransport?
    var store: TransportStore?
    @KeyBundleMechanismActor
    var mechanism: KeyBundleMechanism?
    let logger = Logger(label: "Client")
    var transportDelegate: CypherTransportClientDelegate?
    
    //NEW
    var username: Username
    var deviceId: DeviceId
    var asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>?
    
    
    func handleStream(_ stream:  NIOInboundChannelStream<ByteBuffer>) {
        Task {
            await handleChildChannel(stream, mechanism: await self.mechanism!, transport: await self.transport!, store: self.store!)
        }
    }
    var registrationState: RegistrationState = .full
    weak var mtDelegate: MessengerTransportBridge?
    
    init(
        cypher: CypherMessenger?,
        messenger: NeedleTailMessenger,
        transportState: TransportState,
        transportDelegate: CypherTransportClientDelegate?,
        signer: TransportCreationRequest?,
        clientContext: ClientContext,
        username: Username,
        deviceId: DeviceId
    ) {
        self.cypher = cypher
        self.messenger = messenger
        self.clientContext = clientContext
        self.clientInfo = clientContext.clientInfo
        self.signer = signer
        self.transportState = transportState
        self.transportDelegate = transportDelegate
        self.username = username
        self.deviceId = deviceId
        let group: EventLoopGroup?
#if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            group = NIOTSEventLoopGroup()
        } else {
            logger.error("Sorry, your OS is too old for Network.framework.")
            exit(0)
        }
#else
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        self.eventLoop = group!.next()
        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        self.groupManager = EventLoopGroupManager(provider: provider)
    }
    
    func removeReferences() async {
            eventLoop = nil
            cypher = nil
    }
    
    deinit {}
}

extension NeedleTailClient: Equatable {
    static func == (lhs: NeedleTailClient, rhs: NeedleTailClient) -> Bool {
        return lhs === rhs
    }
}


