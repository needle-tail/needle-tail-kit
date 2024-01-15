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
    var continuation: AsyncStream<NIOAsyncChannelOutboundWriter<ByteBuffer>>.Continuation?
    var inboundContinuation: AsyncStream<NIOAsyncChannelInboundStream<ByteBuffer>>.Continuation?
    let messageParser = MessageParser()
    let logger = Logger(label: "Client")
    var cancelStream = false
    
    struct Configuration: Sendable {
        let ntkBundle: NTKClientBundle
        var transportState: TransportState
        let clientContext: ClientContext
        let serverInfo: ClientContext.ServerClientInfo
        let ntkUser: NTKUser
        let messenger: NeedleTailMessenger
    }
    
    var configuration: Configuration
    var transportConfiguration: NeedleTailCypherTransport.Configuration
    let groupManager: EventLoopGroupManager
    var store: TransportStore?
    var childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>?
    var channelIsActive = false
    var registrationState: RegistrationState = .full
    var writer: NeedleTailWriter?
    var stream: NeedleTailStream?

    init(configuration: Configuration) {
        self.configuration = configuration
        self.transportConfiguration = configuration.ntkBundle.cypherTransport.configuration
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
        childChannel = nil
    }
    
    func finishRegistering(with stream: NeedleTailStream, and writer: NeedleTailWriter) async throws {
        self.stream = stream
        self.writer = writer
        
        if let delegate = configuration.ntkBundle.cypherTransport.delegate {
            await stream.setDelegates(
                self,
                delegate: delegate,
                plugin: transportConfiguration.plugin,
                messenger: transportConfiguration.messenger
            )
        }
        
        let appleToken = transportConfiguration.appleToken ?? ""
        let hasAppleToken = (appleToken != "")
        let name = transportConfiguration.nameToVerify ?? ""
        let registrationState = transportConfiguration.registrationState
        
        // Register User
            try await self.resumeClient(
                writer: writer,
                type: hasAppleToken ? .siwa(appleToken) : .plain(name),
                state: registrationState
            )
    }
}

extension NeedleTailClient: Equatable {
    static func == (lhs: NeedleTailClient, rhs: NeedleTailClient) -> Bool {
        return lhs === rhs
    }
}

#endif
