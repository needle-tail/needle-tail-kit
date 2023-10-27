import Logging
import NeedleTailHelpers
import CypherMessaging
 import NeedleTailProtocol
 import NIOCore
#if canImport(Network)
import NIOTransportServices
#endif

#if (os(macOS) || os(iOS))
struct NTKClientBundle: Sendable {
    let signer: TransportCreationRequest?
    var cypher: CypherMessenger?
    var cypherTransport: NeedleTailCypherTransport
}

actor NeedleTailClient {
    let messageParser = MessageParser()
    let logger = Logger(label: "Client")
    let ntkBundle: NTKClientBundle
    let groupManager: EventLoopGroupManager
    let transportState: TransportState
    let clientContext: ClientContext
    let serverInfo: ClientContext.ServerClientInfo
    let ntkUser: NTKUser
    let messenger: NeedleTailMessenger
    var transport: NeedleTailTransport?
    @KeyBundleMechanismActor
    var mechanism: KeyBundleMechanism?
    @KeyBundleMechanismActor
    var store: TransportStore?
    var childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>?
    var registrationState: RegistrationState = .full
    let delegateJob = JobQueue<NeedleTailCypherTransport.DelegateJob>()
    
    @NeedleTailTransportActor
    func setDelegates(_
                      transport: NeedleTailTransport,
                      delegate: CypherTransportClientDelegate,
                      plugin: NeedleTailPlugin,
                      messenger: NeedleTailMessenger
    ) async -> NeedleTailTransport {
        transport.ctcDelegate = delegate
        transport.ctDelegate = self
        transport.plugin = plugin
        return transport
    }

    init(
        ntkBundle: NTKClientBundle,
        transportState: TransportState,
        clientContext: ClientContext,
        ntkUser: NTKUser,
        messenger: NeedleTailMessenger
    ) {
        self.ntkBundle = ntkBundle
        self.clientContext = clientContext
        self.serverInfo = clientContext.serverInfo
        self.ntkUser = ntkUser
        self.transportState = transportState
        self.messenger = messenger
        var group: EventLoopGroup?
        var usingNetwork = false
#if canImport(Network)
        usingNetwork = true
        if #available(macOS 13, iOS 16, *) {
            group = NIOTSEventLoopGroup()
        } else {
            logger.error("Sorry, your OS is too old for Network.framework.")
            exit(0)
        }
#else
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        self.groupManager = EventLoopGroupManager(provider: provider, usingNetwork: usingNetwork)
    }
    
    deinit {
        //            print("RECLAIMING MEMORY IN CLIENT")
    }
    
    func teardownClient() async {
        transport = nil
        childChannel = nil
        await tearDownKeyMech()
    }
    
    @KeyBundleMechanismActor
    func tearDownKeyMech() async {
        mechanism = nil
        store = nil
    }
}

extension NeedleTailClient: Equatable {
    static func == (lhs: NeedleTailClient, rhs: NeedleTailClient) -> Bool {
        return lhs === rhs
    }
}

#endif
