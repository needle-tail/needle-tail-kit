import NIOSSL
import NIOExtras
import NeedleTailHelpers
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NIOPosix
#if canImport(Network)
import Network
@_spi(AsyncChannel) import NIOTransportServices
#endif

/// `EventLoopGroupManager` can be used to manage an `EventLoopGroup`, either by creating or by sharing an existing one.
///
/// When making network client libraries with SwiftNIO that are supposed to work well on both Apple platforms (macOS,
/// iOS, tvOS, ...) as well as Linux, users often find it tedious to select the right combination of:
///
/// - an `EventLoopGroup`
/// - a bootstrap
/// - a TLS implementation
///
/// The choices to the above need to be compatible, or else the program won't work.
///
/// What makes the task even harder is that as a client library, you often want to share the `EventLoopGroup` with other
/// components. That raises the question of how to choose a bootstrap and a matching TLS implementation without even
/// knowing the concrete `EventLoopGroup` type (it may be `SelectableEventLoop` which is an internal `NIO` types).
/// `EventLoopGroupManager` should support all those use cases with a simple API.
public class EventLoopGroupManager {
    private var group: Optional<EventLoopGroup>
    private let provider: Provider
    
    private var sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
    
    public enum Provider {
        case createNew
        case shared(EventLoopGroup)
    }
    
    /// Initialize the `EventLoopGroupManager` with a `Provder` of `EventLoopGroup`s.
    ///
    /// The `Provider` lets you choose whether to use a `.shared(group)` or to `.createNew`.
    public init(provider: Provider) {
        self.provider = provider
        switch self.provider {
        case .shared(let group):
            self.group = group
        case .createNew:
            self.group = nil
        }
    }
    
    deinit {
        //        assert(self.group == nil, "Please call EventLoopGroupManager.shutdown .")
    }
}

// - MARK: Public API
extension EventLoopGroupManager {
    /// Create a "universal bootstrap" for the given host.
    /// Shutdown the `EventLoopGroupManager`.
    ///
    /// This will release all resources associated with the `EventLoopGroupManager` such as the threads that the
    /// `EventLoopGroup` runs on.
    ///
    /// This method _must_ be called when you're done with this `EventLoopGroupManager`.
    public func shutdown() async throws {
        switch self.provider {
        case .createNew:
            try await self.group?.shutdownGracefully()
            print("shutdown new group")
        case .shared:
            print("shutdown shared group \(String(describing: group))")
            () // nothing to do.
        }
        self.group = nil
    }
}

// - MARK: Error types
extension EventLoopGroupManager {
    /// The provided `EventLoopGroup` is not compatible with this client.
    public struct UnsupportedEventLoopGroupError: Swift.Error {
        var eventLoopGroup: EventLoopGroup
    }
}
enum ELGMErrors: Swift.Error {
    case nilEventLoopGroup
}

// - MARK: Internal functions
extension EventLoopGroupManager {
    
    @_spi(AsyncChannel)
    public func makeAsyncChannel(
        host: String,
        port: Int,
        enableTLS:  Bool = true
    ) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        
        guard let group = self.group else { throw ELGMErrors.nilEventLoopGroup }
        
        @_spi(AsyncChannel)
        func socketChannelCreator() async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
            let sslContext = try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
            let client = ClientBootstrap(group: group)
            let channel: NIOAsyncChannel<ByteBuffer, ByteBuffer> = try await client
                .connectTimeout(.seconds(10))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR), value: 1)
                .connect(host: host, port: port) { channel in
                    channel.eventLoop.makeCompletedFuture {
                       _ = createHandlers(channel)
                        return try NIOAsyncChannel(synchronouslyWrapping: channel)
                    }
                }
                
            let bootstrap = try NIOClientTCPBootstrap(
                client,
                tls: NIOSSLClientTLSProvider(
                    context: sslContext,
                    serverHostname: host
                )
            )
            if enableTLS {
                bootstrap.enableTLS()
            }
            return channel
        }
        
        
#if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
//             We run on a new-enough Darwin so we can use Network.framework
            var connection = NIOTSConnectionBootstrap(group: group)
            let tcpOptions = NWProtocolTCP.Options()
            connection = connection.tcpOptions(tcpOptions)
            if enableTLS {
                let tlsOptions = NWProtocolTLS.Options()
                connection = connection.tlsOptions(tlsOptions)
            }
            let channel: NIOAsyncChannel<ByteBuffer, ByteBuffer> = try await connection
                .channelInitializer({ channel in
                    createHandlers(channel)
                })
                .connectTimeout(.seconds(10))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR), value: 1)
                .connect(host: host, port: port)
            return channel
        } else {
            // We're on Darwin but not new enough for Network.framework, so we fall back on NIO on BSD sockets.
            return try await socketChannelCreator()
        }
#else
        // We are on a non-Darwin platform, so we'll use BSD sockets.
        return try await socketChannelCreator()
#endif
        
        @Sendable func createHandlers(_ channel: Channel) -> EventLoopFuture<Void> {
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandlers([
                    ByteToMessageHandler(
                        LineBasedFrameDecoder()
//                        maximumBufferSize: 16777216
                    )
                ], position: .first)
            }
        }
    }
    
}
