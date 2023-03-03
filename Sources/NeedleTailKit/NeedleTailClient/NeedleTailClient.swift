import Logging
import NeedleTailHelpers
import CypherMessaging
import NeedleTailProtocol
#if canImport(Network)
import NIOTransportServices
#endif


struct NTKClientBundle: Sendable {
    var cypher: CypherMessenger?
    var messenger: NeedleTailMessenger
    let signer: TransportCreationRequest?
}

@NeedleTailClientActor
final class NeedleTailClient {

    let logger = Logger(label: "Client")
    let ntkBundle: NTKClientBundle
    let groupManager: EventLoopGroupManager
    let transportState: TransportState
    let clientContext: ClientContext
    let clientInfo: ClientContext.ServerClientInfo
    let ntkUser: NTKUser
    @NeedleTailTransportActor
    var transport: NeedleTailTransport?
    @KeyBundleMechanismActor
    var mechanism: KeyBundleMechanism?
    var store: TransportStore?
    var childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>?
    var registrationState: RegistrationState = .full
    @NeedleTailTransportActor
    func setDelegates(_
                      delegate: CypherTransportClientDelegate,
                      mtDelegate: MessengerTransportBridge?,
                      plugin: NeedleTailPlugin,
                      emitter: NeedleTailEmitter
    ) async {
        var mtDelegate = mtDelegate
        mtDelegate = transport
        mtDelegate?.ctcDelegate = delegate
        mtDelegate?.ctDelegate = self
        mtDelegate?.emitter = plugin.store.emitter
        mtDelegate?.plugin = plugin
    }
    
    init(
        ntkBundle: NTKClientBundle,
        transportState: TransportState,
        clientContext: ClientContext,
        ntkUser: NTKUser
    ) {
        self.ntkBundle = ntkBundle
        self.clientContext = clientContext
        self.clientInfo = clientContext.clientInfo
        self.ntkUser = ntkUser
        self.transportState = transportState

        var group: EventLoopGroup?
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
        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        self.groupManager = EventLoopGroupManager(provider: provider)
    }
    
    deinit {
//            print("RECLAIMING MEMORY IN CLIENT")
    }
    
    
    func teardownClient() async {
        await teardownTransport()
        await teardownMechanism()
        childChannel = nil
        store = nil
    }
    
    @NeedleTailTransportActor
    func teardownTransport() {
        transport = nil
    }
    
    @KeyBundleMechanismActor
    func teardownMechanism() {
        mechanism = nil
    }
}

extension NeedleTailClient: Equatable {
    static func == (lhs: NeedleTailClient, rhs: NeedleTailClient) -> Bool {
        return lhs === rhs
    }
}


